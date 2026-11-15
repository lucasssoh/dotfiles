//! `RoueWheel` widget: the radial selection wheel itself (drawing,
//! mouse/keyboard hover, animation, confirmation). Generic over the list
//! of sectors received at construction -- no knowledge of "power" or
//! "powerprofile" here, this is what allows this widget to be reused as-is
//! for any future wheel (see config.rs).
//!
//! Drawn entirely in GSK (like card.rs/carousel.rs in Prisme): a black
//! disc, a grey track along its edge, separators, and arcs laid on the
//! track for the hovered and the applied sector -- paths sampled point by
//! point (gsk::PathBuilder has no dedicated arc primitive in this
//! version), stroked or filled via push_stroke/push_fill + append_color.
//! (It was a ring of glass-filled wedges with a cyan tint until the
//! HyperOS pass.)

use gtk4::glib;
use gtk4::prelude::*;
use gtk4::subclass::prelude::*;
use gtk4::{gdk, graphene, gsk, pango};
use std::cell::{Cell, RefCell};
use std::collections::HashMap;
use std::time::Instant;

use crate::color;
use crate::config::Segment;
use crate::icons::{self, IconPair};

/// Convergence speed of the exponential interpolation (fan-out opening +
/// hovered sector highlight) -- same value and reasoning as carousel.rs
/// (~220ms to converge at 95%, independent of refresh rate thanks to the
/// frame clock's real dt).
const EASE_RATE: f64 = 14.0;

const WHEEL_SIZE_PX: i32 = 520;
const OUTER_MARGIN_PX: f64 = 24.0;
/// A more generous hub -- which correspondingly compacts the band occupied
/// by sectors between it and the outer edge (less radial "empty space" in
/// each sector, which now only holds a logo).
const INNER_RADIUS_RATIO: f64 = 0.56;
/// Radius (px) around the center where mouse hover is ignored -- avoids an
/// angle that jumps erratically when the cursor passes very close to the
/// center (atan2(0,0) isn't stably defined), same role as an analog
/// joystick's dead zone.
const HOVER_DEADZONE_PX: f64 = 28.0;
const ARC_STEPS: usize = 20;
/// Display size (px) of the SVG logo in a sector -- grows a bit with `t`
/// on hover, like the old glyph rendering. `ICON_FONT_PX` remains used for
/// the plain-text fallback (see `draw_icon` in snapshot()) -- confirmation
/// sectors, or a missing/invalid icon.
const ICON_SIZE_PX: f64 = 34.0;
const ICON_HOVER_GROW_PX: f64 = 6.0;
const ICON_FONT_PX: f64 = 32.0;
const HUB_ICON_SIZE_PX: f64 = 46.0;
const HUB_LABEL_FONT_PX: f64 = 15.0;
/// Wrap width for the hub label -- device/monitor descriptions (e.g. "Ryzen
/// HD Audio Controller Stéréo analogique") can run well past the hub's own
/// diameter (2 * INNER_RADIUS_RATIO * max_radius, ~264px at the 520px wheel
/// size) as a single line. Comfortably inside that: verified with
/// `pango-view` at the same font/width/wrap settings, a label this long
/// wraps to 3 lines ~83px tall, pushing the outermost line ~67px off
/// center -- the hub circle (radius ~132px) is still ~227px wide there,
/// well clear of this 190px wrap width.
const HUB_LABEL_MAX_WIDTH_PX: f64 = 190.0;
/// Index of Confirm among the confirmation sub-menu's two synthetic
/// sectors (see `enter_confirm`): Cancel on top, Confirm below.
const CONFIRM_INDEX: usize = 1;
const HUB_BORDER_WIDTH_PX: f32 = 3.0;
/// White band marking the "current system state" sector (see the TOML
/// `active` field, e.g. the current power profile) -- drawn slightly
/// INSIDE the outer edge (ACTIVE_BAND_INSET_PX), not right on it, to stay
/// visually WITHIN the colored sector rather than straddling its
/// anti-aliasing.
/// The grey track along the disc's edge, and the arcs laid on it (the
/// selection, the applied state): its width, how far in from the disc's
/// edge its centre runs, and the gap left at each end of a sector's arc
/// so two neighbouring arcs never touch.
const TRACK_WIDTH_PX: f32 = 7.0;
/// The shell's white ink, as (r, g, b): the hover arc and the hub.
const WHITE: (f32, f32, f32) = (0.949, 0.949, 0.969);
/// The hub's second line ("current", "now: ...", "back to the wheel").
const HUB_SUB_FONT_PX: f64 = 12.0;
const TRACK_INSET_PX: f64 = 16.0;
const ARC_GAP_PX: f64 = 18.0;

mod imp {
    use super::*;

    #[derive(Default)]
    pub struct Wheel {
        /// Root wheel sectors, never modified after construction -- used to
        /// go back when leaving the confirmation sub-menu (see
        /// `Wheel::exit_confirm`).
        pub root_segments: RefCell<Vec<Segment>>,
        /// Sectors actually displayed/hovered -- identical to
        /// `root_segments`, except during a confirmation where they
        /// temporarily hold [Confirm, Cancel].
        pub segments: RefCell<Vec<Segment>>,
        /// Textures rasterized once at construction (see `RoueWheel::new`),
        /// indexed by the `icon` field of ROOT sectors only -- the
        /// synthetic Confirm/Cancel sectors (see `enter_confirm`) never
        /// appear in it, `snapshot()` then falls back to plain text
        /// rendering for them (see `draw_icon`).
        pub icons: RefCell<HashMap<String, IconPair>>,
        /// Index (in `root_segments`) of the sector marked `active = true`
        /// in the TOML, if any -- computed once at construction (see
        /// `RoueWheel::new`), never recomputed afterward (a wheel doesn't
        /// change state while it's displayed, which is exactly why the
        /// generator script regenerates it on EVERY opening, see
        /// wheels/powerprofile on the script side). Ignored during a
        /// confirmation (`confirming`): the displayed sectors are then
        /// Confirm/Cancel, not the root sectors.
        pub active_index: Cell<Option<usize>>,
        /// The aimed sector, None until something aims (the mouse past the
        /// dead zone, a click, an arrow, a digit) on this level of the
        /// wheel (root or confirmation sub-menu). Nothing is drawn as
        /// selected before that, so what is lit is always what Enter or a
        /// click would run.
        pub hovered: Cell<Option<usize>>,
        /// The wheel's name, shown in the hub while nothing is aimed.
        pub title: RefCell<String>,
        /// Last pointer position seen, in the widget's frame.
        pub last_pointer: Cell<Option<(f64, f64)>>,
        /// Where the pointer was when the confirmation sub-menu opened. A
        /// click there does not aim: it is the second click of a double
        /// click on a destructive sector, which would otherwise land on
        /// Confirm whenever that sector sits in the lower half. Cleared
        /// once the pointer moves away.
        pub confirm_anchor: Cell<Option<(f64, f64)>>,
        /// 0 = closed, 1 = fully open -- animates BOTH the radius and the
        /// alpha of everything drawn (fan-out effect on opening).
        pub open_progress: Cell<f64>,
        /// 0 = hovered sector not yet brought forward, 1 = highlight fully
        /// applied -- resets to 0 on every hovered-sector change (see
        /// `set_hover_index`).
        pub hover_anim: Cell<f64>,
        pub confirming: Cell<bool>,
        pub pending: RefCell<Option<Segment>>,
        pub start: Cell<Option<Instant>>,
        pub last_frame_us: Cell<Option<i64>>,
        pub commit_cb: RefCell<Option<Box<dyn Fn(&Segment)>>>,
    }

    #[glib::object_subclass]
    impl ObjectSubclass for Wheel {
        const NAME: &'static str = "RoueWheel";
        type Type = super::RoueWheel;
        type ParentType = gtk4::Widget;
    }

    impl ObjectImpl for Wheel {}

    impl WidgetImpl for Wheel {
        // Fixed, constant size (unlike Card/Carousel in Prisme): nothing
        // here changes the size ALLOCATED to the widget from one frame to
        // the next, only what's drawn inside it (radius, alpha) animates
        // -- measure() therefore doesn't need the "(0,0,-1,-1)" workaround
        // used there to avoid a queue_resize loop.
        fn measure(&self, _orientation: gtk4::Orientation, _for_size: i32) -> (i32, i32, i32, i32) {
            (WHEEL_SIZE_PX, WHEEL_SIZE_PX, -1, -1)
        }

        fn snapshot(&self, snapshot: &gtk4::Snapshot) {
            let widget = self.obj();
            let w = widget.width() as f64;
            let h = widget.height() as f64;
            if w <= 0.0 || h <= 0.0 {
                return;
            }
            let segments = self.segments.borrow();
            let n = segments.len();
            if n == 0 {
                return;
            }

            let open = self.open_progress.get();
            let cx = w / 2.0;
            let cy = h / 2.0;
            let max_radius = (w.min(h) / 2.0 - OUTER_MARGIN_PX).max(0.0);
            let outer_radius = max_radius * open;
            let inner_radius = max_radius * INNER_RADIUS_RATIO * open;

            let angle_per = std::f64::consts::TAU / n as f64;
            let base = -std::f64::consts::FRAC_PI_2 - angle_per / 2.0;
            let hovered = self.hovered.get();
            let hover_t = self.hover_anim.get() as f32;

            let confirming = self.confirming.get();
            // Ignored during a confirmation -- see the field's doc.
            let active_index = if confirming { None } else { self.active_index.get() };

            // HyperOS pass -- the "C" of the mockups ("arc de sélection"):
            // one black disc instead of a ring of glass wedges, a grey track
            // along its edge, thin separators between sectors, and the
            // hovered sector marked by a white arc laid on the track while
            // its icon turns from grey to white. The same language as the
            // bar's volume popup (a thick arc on a track), and no tint of
            // its own -- only a destructive confirmation turns red.
            let full = graphene::Rect::new(0.0, 0.0, w as f32, h as f32);
            let track_radius = (outer_radius - TRACK_INSET_PX * open).max(inner_radius + 1.0);

            // The disc.
            let disc = circle_path(cx, cy, outer_radius);
            snapshot.push_fill(&disc, gsk::FillRule::Winding);
            snapshot.append_color(&gdk::RGBA::new(0.0, 0.0, 0.0, (0.94 * open) as f32), &full);
            snapshot.pop();
            snapshot.push_stroke(&disc, &gsk::Stroke::new(1.0));
            snapshot.append_color(&gdk::RGBA::new(1.0, 1.0, 1.0, (0.08 * open) as f32), &full);
            snapshot.pop();

            // The track. Dark red for the whole confirmation sub-menu -- the
            // "C2" of the mockups: you know you are somewhere irreversible
            // before aiming at anything.
            let track = circle_path(cx, cy, track_radius);
            snapshot.push_stroke(&track, &gsk::Stroke::new(TRACK_WIDTH_PX));
            let track_rgba = if confirming {
                gdk::RGBA::new(0.227, 0.110, 0.125, open as f32)
            } else {
                gdk::RGBA::new(0.165, 0.165, 0.184, open as f32)
            };
            snapshot.append_color(&track_rgba, &full);
            snapshot.pop();

            for (i, seg) in segments.iter().enumerate() {
                let t = if Some(i) == hovered { hover_t } else { 0.0 };
                let accent = color::resolve(seg.accent.as_deref()).rgb;
                let angle_left = base + i as f64 * angle_per;
                let angle_right = base + (i + 1) as f64 * angle_per;

                // Separator on this sector's left edge, from just outside
                // the hub to just inside the track.
                if n > 1 {
                    let sep = gsk::PathBuilder::new();
                    let (r0, r1) = (inner_radius + 6.0, track_radius - TRACK_WIDTH_PX as f64 - 6.0);
                    sep.move_to((cx + r0 * angle_left.cos()) as f32, (cy + r0 * angle_left.sin()) as f32);
                    sep.line_to((cx + r1 * angle_left.cos()) as f32, (cy + r1 * angle_left.sin()) as f32);
                    snapshot.push_stroke(&sep.to_path(), &gsk::Stroke::new(1.5));
                    snapshot.append_color(&gdk::RGBA::new(0.122, 0.122, 0.137, open as f32), &full);
                    snapshot.pop();
                }

                if open <= 0.05 {
                    continue;
                }

                // The applied state (current profile, current layout...):
                // this sector's stretch of the track in its own colour,
                // softened -- the "P3" of the mockups: colour marks what
                // IS applied, never what is being aimed at. White for a
                // sector without one. Ignored during a confirmation.
                let is_state = active_index == Some(i);
                let arc = outer_arc_path(cx, cy, track_radius, angle_left, angle_right, ARC_GAP_PX);
                let cap = gsk::Stroke::new(TRACK_WIDTH_PX);
                cap.set_line_cap(gsk::LineCap::Round);
                if is_state {
                    snapshot.push_stroke(&arc, &cap);
                    snapshot.append_color(&gdk::RGBA::new(accent.0, accent.1, accent.2, 0.55 * open as f32), &full);
                    snapshot.pop();
                }
                // The selection: the same stretch in white, fading in with
                // the hover -- or in red on a destructive confirmation.
                if t > 0.001 {
                    let sel = if confirming { accent } else { WHITE };
                    snapshot.push_stroke(&arc, &cap);
                    snapshot.append_color(&gdk::RGBA::new(sel.0, sel.1, sel.2, open as f32 * t), &full);
                    snapshot.pop();
                }

                let mid_angle = (angle_left + angle_right) / 2.0;
                let mid_radius = (inner_radius + track_radius) / 2.0;
                let px = cx + mid_radius * mid_angle.cos();
                let py = cy + mid_radius * mid_angle.sin();
                let size = ICON_SIZE_PX + t as f64 * ICON_HOVER_GROW_PX;
                draw_icon(&widget, snapshot, &self.icons.borrow(), seg, px, py, size, t, open, is_state, confirming);
            }

            // Central hub -- shows the icon + label of the currently
            // hovered sector, an immediate readout of the current choice
            // (like the weapon name centered in a game's wheel). Black on
            // the black disc, set apart by a faint rim.
            if open > 0.02 {
                let hub_path = circle_path(cx, cy, inner_radius);
                let active_seg = active_index.and_then(|a| segments.get(a).map(|s| (a, s)));

                // Rim: the applied sector's colour when the wheel has one
                // ("P3": the hub says which state is current), a faint
                // white line otherwise.
                if let Some((_, a)) = active_seg {
                    let c = color::resolve(a.accent.as_deref()).rgb;
                    snapshot.push_stroke(&hub_path, &gsk::Stroke::new(HUB_BORDER_WIDTH_PX));
                    snapshot.append_color(&gdk::RGBA::new(c.0, c.1, c.2, 0.55 * open as f32), &full);
                    snapshot.pop();
                } else {
                    snapshot.push_stroke(&hub_path, &gsk::Stroke::new(1.0));
                    snapshot.append_color(&gdk::RGBA::new(1.0, 1.0, 1.0, (0.08 * open) as f32), &full);
                    snapshot.pop();
                }

                if let Some(seg) = hovered.and_then(|h| segments.get(h)) {
                    let seg_accent = color::resolve(seg.accent.as_deref()).rgb;
                    let danger = confirming && hovered == Some(CONFIRM_INDEX);

                    // What the hub says. On a confirmation ("C2") it asks
                    // the question about the pending action; otherwise just
                    // the hovered sector's name. (A "now: <profile>" line
                    // was tried under it and dropped: the applied state's
                    // colour on the rim and its arc already says it.)
                    let pending_label = self.pending.borrow().as_ref().map(|p| p.label.clone());
                    let (title, sub): (String, Option<String>) = if confirming {
                        if danger {
                            (format!("{}?", pending_label.unwrap_or_else(|| seg.label.clone())),
                             Some("click or Enter to confirm".into()))
                        } else {
                            ("Cancel".into(), Some("back to the wheel".into()))
                        }
                    } else {
                        (seg.label.clone(), None)
                    };

                    let make = |text: &str, px: f64| {
                        let mut font = pango::FontDescription::new();
                        font.set_absolute_size(px * pango::SCALE as f64);
                        let l = widget.create_pango_layout(Some(text));
                        l.set_font_description(Some(&font));
                        // Long labels wrap inside the hub instead of
                        // overflowing it; the BOX is centred on `cx` and
                        // the layout centres the ink inside it (see
                        // HUB_LABEL_MAX_WIDTH_PX -- pixel_size() only
                        // reports the tight ink width).
                        l.set_width((HUB_LABEL_MAX_WIDTH_PX * pango::SCALE as f64) as i32);
                        l.set_wrap(pango::WrapMode::WordChar);
                        l.set_alignment(pango::Alignment::Center);
                        l
                    };
                    let title_l = make(&title, HUB_LABEL_FONT_PX);
                    let (_, th) = title_l.pixel_size();
                    let sub_l = sub.as_deref().map(|t| make(t, HUB_SUB_FONT_PX));
                    let sh = sub_l.as_ref().map(|l| l.pixel_size().1).unwrap_or(0);

                    const GAP: f64 = 6.0;
                    const SUB_GAP: f64 = 3.0;
                    let block_h = HUB_ICON_SIZE_PX + GAP + th as f64
                        + if sub_l.is_some() { SUB_GAP + sh as f64 } else { 0.0 };
                    let top = cy - block_h / 2.0;

                    // Hub icon: white, red on the confirmation's Confirm.
                    draw_icon(&widget, snapshot, &self.icons.borrow(), seg, cx, top + HUB_ICON_SIZE_PX / 2.0,
                              HUB_ICON_SIZE_PX, 1.0, open, false, danger);

                    let title_c = if danger { seg_accent } else { WHITE };
                    snapshot.save();
                    snapshot.translate(&graphene::Point::new(
                        (cx - HUB_LABEL_MAX_WIDTH_PX / 2.0) as f32,
                        (top + HUB_ICON_SIZE_PX + GAP) as f32,
                    ));
                    snapshot.append_layout(&title_l, &gdk::RGBA::new(title_c.0, title_c.1, title_c.2, open as f32));
                    snapshot.restore();

                    if let Some(l) = sub_l {
                        snapshot.save();
                        snapshot.translate(&graphene::Point::new(
                            (cx - HUB_LABEL_MAX_WIDTH_PX / 2.0) as f32,
                            (top + HUB_ICON_SIZE_PX + GAP + th as f64 + SUB_GAP) as f32,
                        ));
                        snapshot.append_layout(&l, &gdk::RGBA::new(0.557, 0.557, 0.576, open as f32));
                        snapshot.restore();
                    }
                } else {
                    // Nothing aimed: the wheel's name, or the pending
                    // question on a confirmation.
                    let text = match self.pending.borrow().as_ref() {
                        Some(p) if confirming => format!("{}?", p.label),
                        _ => self.title.borrow().clone(),
                    };
                    let mut font = pango::FontDescription::new();
                    font.set_absolute_size(HUB_LABEL_FONT_PX * pango::SCALE as f64);
                    let l = widget.create_pango_layout(Some(&text));
                    l.set_font_description(Some(&font));
                    l.set_width((HUB_LABEL_MAX_WIDTH_PX * pango::SCALE as f64) as i32);
                    l.set_wrap(pango::WrapMode::WordChar);
                    l.set_alignment(pango::Alignment::Center);
                    let (_, th) = l.pixel_size();
                    snapshot.save();
                    snapshot.translate(&graphene::Point::new(
                        (cx - HUB_LABEL_MAX_WIDTH_PX / 2.0) as f32,
                        (cy - th as f64 / 2.0) as f32,
                    ));
                    snapshot.append_layout(&l, &gdk::RGBA::new(0.557, 0.557, 0.576, open as f32));
                    snapshot.restore();
                }
            }
        }
    }

    impl Wheel {
        pub(super) fn tick(&self, clock: &gdk::FrameClock) {
            let now_us = clock.frame_time();
            let dt = match self.last_frame_us.get() {
                Some(prev) => ((now_us - prev).max(0) as f64 / 1_000_000.0).min(0.1),
                None => 1.0 / 60.0,
            };
            self.last_frame_us.set(Some(now_us));
            if self.start.get().is_none() {
                self.start.set(Some(Instant::now()));
            }

            let op = self.open_progress.get();
            let ha = self.hover_anim.get();
            let op_moving = (1.0 - op).abs() > 0.0005;
            let ha_moving = (1.0 - ha).abs() > 0.0005;
            // Nothing to animate -- doesn't request another frame, like
            // carousel.rs::tick (near-zero cost once stabilized).
            if !op_moving && !ha_moving {
                return;
            }

            let ease = 1.0 - (-EASE_RATE * dt).exp();
            if op_moving {
                let next = op + (1.0 - op) * ease;
                self.open_progress.set(if (1.0 - next).abs() < 0.0005 { 1.0 } else { next });
            }
            if ha_moving {
                let next = ha + (1.0 - ha) * ease;
                self.hover_anim.set(if (1.0 - next).abs() < 0.0005 { 1.0 } else { next });
            }
            self.obj().queue_draw();
        }
    }
}

/// Draws a sector's logo centered at `(cx, cy)`, a square of side `size`
/// -- pre-rasterized SVG texture if `seg` has one in `icons` (see
/// icons.rs, indexed by `icons::cache_key`), otherwise falls back to a
/// plain Pango glyph (synthetic Confirm/Cancel sectors, or a
/// missing/invalid icon -- see `icons::load`). `t` animates a crossfade
/// toward the SECTOR'S accent color on hover (0 = normal color, 1 = full
/// accent, see `color::resolve`); `open` multiplies the alpha (fade-in on
/// opening).
fn draw_icon(
    widget: &RoueWheel,
    snapshot: &gtk4::Snapshot,
    icons: &HashMap<String, IconPair>,
    seg: &Segment,
    cx: f64,
    cy: f64,
    size: f64,
    t: f32,
    open: f64,
    // Rest in the sector's colour (it is the applied state) rather than
    // grey; hover toward its colour (a confirmation's danger) rather than
    // white.
    base_accent: bool,
    hover_accent: bool,
) {
    if let Some(pair) = icons.get(&icons::cache_key(seg)) {
        let rect = graphene::Rect::new(
            (cx - size / 2.0) as f32,
            (cy - size / 2.0) as f32,
            size as f32,
            size as f32,
        );
        // Base raster, then the hover raster crossfaded on top with `t` --
        // crossfading pre-baked rasters rather than a GPU colour-matrix
        // recolour (see icons::load for the three).
        let base = if base_accent { &pair.accent } else { &pair.normal };
        let over = if hover_accent { &pair.accent } else { &pair.hover };
        draw_texture(snapshot, base, &rect, open);
        if t > 0.001 {
            draw_texture(snapshot, over, &rect, open * t as f64);
        }
        return;
    }

    // Text fallback -- synthetic Confirm/Cancel sectors (no associated SVG
    // file, see `enter_confirm`), or a missing/invalid icon (see
    // `icons::load`).
    let accent = color::resolve(seg.accent.as_deref()).rgb;
    let color = text_color(t, open as f32, if hover_accent { accent } else { WHITE });
    let mut font = pango::FontDescription::new();
    font.set_absolute_size((ICON_FONT_PX + t as f64 * 4.0) * pango::SCALE as f64);
    let layout = widget.create_pango_layout(Some(&seg.icon));
    layout.set_font_description(Some(&font));
    let (iw, ih) = layout.pixel_size();
    snapshot.save();
    snapshot.translate(&graphene::Point::new(
        (cx - iw as f64 / 2.0) as f32,
        (cy - ih as f64 / 2.0) as f32,
    ));
    snapshot.append_layout(&layout, &color);
    snapshot.restore();
}

fn draw_texture(snapshot: &gtk4::Snapshot, texture: &gdk::Texture, rect: &graphene::Rect, alpha: f64) {
    if alpha <= 0.001 {
        return;
    }
    if alpha < 0.999 {
        snapshot.push_opacity(alpha);
        snapshot.append_scaled_texture(texture, gsk::ScalingFilter::Trilinear, rect);
        snapshot.pop();
    } else {
        snapshot.append_scaled_texture(texture, gsk::ScalingFilter::Trilinear, rect);
    }
}

/// EXACT angle and radius of the point on ray `theta` (length `r`) offset
/// perpendicularly by `offset` (positive = toward increasing angles) --
/// direct geometric identity (right triangle radius/perpendicular), never
/// an atan2(y,x) over cartesian coordinates: this avoids any angle wrap at
/// ±π, including for the last sectors whose `angle_right` exceeds 2π in
/// raw value (see `base` in snapshot()). Shared by `wedge_path` (sector
/// edges) and `outer_arc_path` (active-state band) -- both must stay
/// aligned on the same gap.
fn offset_ray(theta: f64, r: f64, offset: f64) -> (f64, f64) {
    (theta + offset.atan2(r), r.hypot(offset))
}

/// Plain arc (NOT a closed sector, unlike `wedge_path`) along a circle of
/// radius `radius`, offset by the same `gap_px` as the sector edges --
/// used as the active-state band's path (see ACTIVE_BAND_WIDTH_PX), so it
/// stays aligned with the sector's visible edges rather than overflowing
/// past them.
fn outer_arc_path(cx: f64, cy: f64, radius: f64, angle_left: f64, angle_right: f64, gap_px: f64) -> gsk::Path {
    let half_gap = (gap_px / 2.0).max(0.0);
    let (a_l, r_l) = offset_ray(angle_left, radius, half_gap);
    let (a_r, r_r) = offset_ray(angle_right, radius, -half_gap);

    let builder = gsk::PathBuilder::new();
    for step in 0..=ARC_STEPS {
        let t = step as f64 / ARC_STEPS as f64;
        let a = a_l + (a_r - a_l) * t;
        let r = r_l + (r_r - r_l) * t;
        let x = cx + r * a.cos();
        let y = cy + r * a.sin();
        if step == 0 {
            builder.move_to(x as f32, y as f32);
        } else {
            builder.line_to(x as f32, y as f32);
        }
    }
    builder.to_path()
}

fn circle_path(cx: f64, cy: f64, r: f64) -> gsk::Path {
    const STEPS: usize = 48;
    let builder = gsk::PathBuilder::new();
    for step in 0..=STEPS {
        let a = std::f64::consts::TAU * step as f64 / STEPS as f64;
        let x = cx + r * a.cos();
        let y = cy + r * a.sin();
        if step == 0 {
            builder.move_to(x as f32, y as f32);
        } else {
            builder.line_to(x as f32, y as f32);
        }
    }
    builder.close();
    builder.to_path()
}

/// A text-fallback sector's colour -- grey at rest, `accent` once hovered
/// (`t` -> 1): white, or red for a confirmation's Confirm.
fn text_color(t: f32, open: f32, accent: (f32, f32, f32)) -> gdk::RGBA {
    let base = (0.557_f32, 0.557, 0.576);
    gdk::RGBA::new(
        base.0 + (accent.0 - base.0) * t,
        base.1 + (accent.1 - base.1) * t,
        base.2 + (accent.2 - base.2) * t,
        open,
    )
}

glib::wrapper! {
    /// Generic radial selection wheel -- all the logic lives in
    /// `imp::Wheel` (standard GObject subclass pattern, like Card/Carousel
    /// in Prisme).
    pub struct RoueWheel(ObjectSubclass<imp::Wheel>) @extends gtk4::Widget;
}

impl RoueWheel {
    /// Builds the wheel with its root sectors and starts the animation
    /// loop (fan-out on opening + hover highlight).
    pub fn new(title: &str, segments: Vec<Segment>) -> Self {
        let wheel: Self = glib::Object::builder().build();
        *wheel.imp().title.borrow_mut() = title.to_string();
        // No hexpand/vexpand/halign/valign here -- centering the
        // wheel+sidebar block on screen is handled by the root Box in
        // main.rs (halign/valign=Center on it, the wheel just keeps its
        // fixed size via measure()), not by the wheel itself.

        // Rasterized once here, from the ROOT sectors only -- the
        // synthetic Confirm/Cancel sectors (see `enter_confirm`) have no
        // associated file, `draw_icon` falls back to plain text for them.
        *wheel.imp().icons.borrow_mut() = icons::load(&segments);

        // At most one `active = true` sector -- computed once here (see
        // the field's doc in imp::Wheel), before `segments` gets moved
        // below.
        wheel.imp().active_index.set(segments.iter().position(|s| s.active));

        *wheel.imp().root_segments.borrow_mut() = segments.clone();
        *wheel.imp().segments.borrow_mut() = segments;

        let wheel_weak = wheel.downgrade();
        wheel.add_tick_callback(move |_, clock| {
            if let Some(wheel) = wheel_weak.upgrade() {
                wheel.imp().tick(clock);
            }
            glib::ControlFlow::Continue
        });

        wheel
    }

    /// Aims at the sector under `(x, y)` (the widget's frame), from a
    /// pointer motion -- only the angle from the centre counts, like an
    /// analog stick. Ignored inside the dead zone (see HOVER_DEADZONE_PX),
    /// and on a confirmation until the pointer leaves where it was when
    /// the sub-menu opened (see `confirm_anchor`).
    pub fn hover_from_point(&self, x: f64, y: f64) {
        self.imp().last_pointer.set(Some((x, y)));
        if self.still_on_anchor(x, y) {
            return;
        }
        self.imp().confirm_anchor.set(None);
        self.aim_at(x, y);
    }

    /// Aims at the sector under a click, before `activate_hovered` --
    /// without it a click validated whatever the last MOTION had aimed
    /// at, and nothing at all when the pointer had not moved since the
    /// wheel opened.
    pub fn aim_at_click(&self, x: f64, y: f64) {
        if self.still_on_anchor(x, y) {
            return;
        }
        self.aim_at(x, y);
    }

    fn still_on_anchor(&self, x: f64, y: f64) -> bool {
        const SLOP_PX: f64 = 6.0;
        self.imp()
            .confirm_anchor
            .get()
            .is_some_and(|(ax, ay)| (x - ax).hypot(y - ay) < SLOP_PX)
    }

    fn aim_at(&self, x: f64, y: f64) {
        let w = self.width() as f64;
        let h = self.height() as f64;
        if w <= 0.0 || h <= 0.0 {
            return;
        }
        let dx = x - w / 2.0;
        let dy = y - h / 2.0;
        if dx.hypot(dy) < HOVER_DEADZONE_PX {
            return;
        }
        let n = self.imp().segments.borrow().len();
        if n == 0 {
            return;
        }
        let angle_per = std::f64::consts::TAU / n as f64;
        let base = -std::f64::consts::FRAC_PI_2 - angle_per / 2.0;
        let theta = dy.atan2(dx);
        let rel = (theta - base).rem_euclid(std::f64::consts::TAU);
        let index = (rel / angle_per).floor() as usize % n;
        self.set_hover_index(index);
    }

    /// Moves the aim by `delta` sectors (keyboard). The first press, with
    /// nothing aimed yet, lands on the top sector whatever its direction.
    pub fn move_hover(&self, delta: i32) {
        let n = self.imp().segments.borrow().len();
        if n == 0 {
            return;
        }
        let next = match self.imp().hovered.get() {
            None => 0,
            Some(cur) => (cur as i32 + delta).rem_euclid(n as i32) as usize,
        };
        self.set_hover_index(next);
    }

    /// Aims at sector `index` directly (a digit, or the pointer's angle).
    pub fn set_hover_index(&self, index: usize) {
        let n = self.imp().segments.borrow().len();
        if n == 0 || index >= n {
            return;
        }
        if self.imp().hovered.get() != Some(index) {
            self.imp().hovered.set(Some(index));
            self.imp().hover_anim.set(0.0);
            self.queue_draw();
        }
    }

    /// Whether something is aimed on this level of the wheel.
    pub fn is_aimed(&self) -> bool {
        self.imp().hovered.get().is_some()
    }

    /// Runs the aimed sector. Returns `true` if the caller should close
    /// the window now (an action ran), `false` if the wheel stays open
    /// (nothing aimed, or switching to/from the Confirm/Cancel sub-menu).
    ///
    /// With nothing aimed, Enter or a click does nothing: the wheel stays
    /// open. The key-release path (`--commit`) checks `is_aimed` first and
    /// closes instead, so a quick tap of the key that opens the wheel
    /// still just dismisses it (see main.rs).
    pub fn activate_hovered(&self) -> bool {
        let imp = self.imp();
        let Some(idx) = imp.hovered.get() else {
            return false;
        };

        if imp.confirming.get() {
            if idx == CONFIRM_INDEX {
                let pending = imp.pending.borrow().clone();
                self.exit_confirm();
                if let Some(seg) = pending {
                    if let Some(cb) = imp.commit_cb.borrow().as_ref() {
                        cb(&seg);
                    }
                }
                true
            } else {
                self.exit_confirm();
                false
            }
        } else {
            let Some(seg) = imp.segments.borrow().get(idx).cloned() else {
                return true;
            };
            if seg.confirm {
                self.enter_confirm(seg);
                false
            } else {
                if let Some(cb) = imp.commit_cb.borrow().as_ref() {
                    cb(&seg);
                }
                true
            }
        }
    }

    pub fn is_confirming(&self) -> bool {
        self.imp().confirming.get()
    }

    /// Returns to the root wheel from the confirmation sub-menu (Escape),
    /// without running anything. Does nothing if not currently confirming
    /// -- it's then up to the caller (main.rs) to close the window
    /// instead.
    pub fn cancel_confirm(&self) {
        if self.imp().confirming.get() {
            self.exit_confirm();
        }
    }

    /// Called only when a final action must run: never for a `confirm`
    /// sector until it has been confirmed.
    pub fn connect_commit(&self, f: impl Fn(&Segment) + 'static) {
        *self.imp().commit_cb.borrow_mut() = Some(Box::new(f));
    }

    fn enter_confirm(&self, seg: Segment) {
        let imp = self.imp();
        // Cloned BEFORE moving `seg` into `pending` below -- it's the ROOT
        // sector currently being confirmed that carries this tint (see its
        // doc in config.rs), not a choice independent from the sub-menu.
        let confirm_accent = seg.confirm_accent.clone();
        imp.confirming.set(true);
        *imp.pending.borrow_mut() = Some(seg);
        // Cancel first (top half), Confirm second (bottom half). Confirm
        // picks up `confirm_accent` from the root sector, Cancel never does.
        *imp.segments.borrow_mut() = vec![
            Segment {
                icon: "✗".into(),
                label: "Cancel".into(),
                action: String::new(),
                confirm: false,
                accent: None,
                confirm_accent: None,
                active: false,
            },
            Segment {
                icon: "✓".into(),
                label: "Confirm".into(),
                action: String::new(),
                confirm: false,
                accent: confirm_accent,
                confirm_accent: None,
                active: false,
            },
        ];
        // Nothing aimed: the sub-menu has to be aimed at again, the
        // gesture that reached the root sector does not count here.
        imp.hovered.set(None);
        imp.confirm_anchor.set(imp.last_pointer.get());
        self.queue_draw();
    }

    fn exit_confirm(&self) {
        let imp = self.imp();
        imp.confirming.set(false);
        *imp.pending.borrow_mut() = None;
        *imp.segments.borrow_mut() = imp.root_segments.borrow().clone();
        imp.hovered.set(None);
        imp.confirm_anchor.set(None);
        self.queue_draw();
    }
}
