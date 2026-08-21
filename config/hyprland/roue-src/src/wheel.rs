//! `RoueWheel` widget: the radial selection wheel itself (drawing,
//! mouse/keyboard hover, animation, confirmation). Generic over the list
//! of sectors received at construction -- no knowledge of "power" or
//! "powerprofile" here, this is what allows this widget to be reused as-is
//! for any future wheel (see config.rs).
//!
//! Drawn entirely in GSK (like card.rs/carousel.rs in Prisme): each sector
//! is a polygon sampled along its two arcs (gsk::PathBuilder has no
//! dedicated arc primitive in this version), filled via
//! push_fill/append_color, exactly the same technique as card.rs's
//! parallelogram -- just with more points.

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
/// Total width (px, measured perpendicular to the separating radius) of
/// the gap between two sectors -- NOT a constant angle: see `wedge_path`
/// for why (a constant angle makes both edges converge to a point at the
/// center, which is exactly what we want to avoid).
const WEDGE_GAP_PX: f64 = 10.0;
const HOVER_RADIUS_BOOST_PX: f64 = 12.0;
/// Radius (px) around the center where mouse hover is ignored -- avoids an
/// angle that jumps erratically when the cursor passes very close to the
/// center (atan2(0,0) isn't stably defined), same role as an analog
/// joystick's dead zone.
const HOVER_DEADZONE_PX: f64 = 28.0;
const ARC_STEPS: usize = 20;
/// Corner radius for the 4 sharp vertices of each wedge (where a straight
/// radial-ish edge meets the outer/inner arc) -- "tout arrondir", no
/// pointed corners anywhere, asked for. See `round_corner`.
const WEDGE_CORNER_RADIUS: f64 = 10.0;
/// Points sampled per rounded corner -- see `round_corner`.
const CORNER_STEPS: usize = 8;
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
/// Indices of the confirmation sub-menu's synthetic sectors (see
/// `enter_confirm`) -- Cancel first (default position, see its doc),
/// Confirm second.
const CANCEL_INDEX: usize = 0;
const CONFIRM_INDEX: usize = 1;
const HUB_BORDER_WIDTH_PX: f32 = 3.0;
/// White band marking the "current system state" sector (see the TOML
/// `active` field, e.g. the current power profile) -- drawn slightly
/// INSIDE the outer edge (ACTIVE_BAND_INSET_PX), not right on it, to stay
/// visually WITHIN the colored sector rather than straddling its
/// anti-aliasing.
const ACTIVE_BAND_WIDTH_PX: f32 = 4.0;
const ACTIVE_BAND_INSET_PX: f64 = 7.0;

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
        pub hovered: Cell<usize>,
        /// Has aiming happened at least once (mouse outside the dead zone,
        /// arrow key, digit) since this wheel level opened (root or
        /// confirmation sub-menu) -- see `activate_hovered`: without
        /// movement, confirming NEVER runs the default sector (index 0),
        /// it cancels instead.
        pub moved: Cell<bool>,
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

            for (i, seg) in segments.iter().enumerate() {
                let t = if i == hovered { hover_t } else { 0.0 };
                // This sector's tint -- its TOML `accent` field (cyan by
                // default if absent, see color.rs), except the "Confirm"
                // sector of the confirmation sub-menu which forces red at
                // construction time (see `enter_confirm`) rather than
                // through a special case here: a single mechanism for both.
                let accent = color::resolve(seg.accent.as_deref()).rgb;
                // "Pure" cut angles, with NO trimming -- the gap between
                // sectors is now handled at constant pixel width inside
                // wedge_path (see its doc), not by trimming these angles.
                let angle_left = base + i as f64 * angle_per;
                let angle_right = base + (i + 1) as f64 * angle_per;
                let boost = HOVER_RADIUS_BOOST_PX * t as f64 * open;
                let path = wedge_path(
                    cx,
                    cy,
                    inner_radius,
                    outer_radius + boost,
                    angle_left,
                    angle_right,
                    WEDGE_GAP_PX * open,
                );

                snapshot.push_fill(&path, gsk::FillRule::Winding);
                let full = graphene::Rect::new(0.0, 0.0, w as f32, h as f32);
                snapshot.append_color(&wedge_color(t, open as f32, accent), &full);
                snapshot.pop();

                if open <= 0.05 {
                    continue;
                }

                // Current-state band -- visible even without hover (unlike
                // the `t` highlight), to spot the applied state at a
                // glance even before aiming. Follows the same OUTER radius
                // as the sector (so its `boost` too if it's also hovered),
                // just slightly inset (ACTIVE_BAND_INSET_PX).
                if active_index == Some(i) {
                    let band_radius = (outer_radius + boost - ACTIVE_BAND_INSET_PX).max(inner_radius + 1.0);
                    let band_path = outer_arc_path(cx, cy, band_radius, angle_left, angle_right, WEDGE_GAP_PX * open);
                    let stroke = gsk::Stroke::new(ACTIVE_BAND_WIDTH_PX);
                    snapshot.push_stroke(&band_path, &stroke);
                    snapshot.append_color(&gdk::RGBA::new(1.0, 1.0, 1.0, open as f32), &full);
                    snapshot.pop();
                }

                let mid_angle = (angle_left + angle_right) / 2.0;
                let mid_radius = (inner_radius + outer_radius + boost) / 2.0;
                let px = cx + mid_radius * mid_angle.cos();
                let py = cy + mid_radius * mid_angle.sin();

                // Just the logo in the sector -- the text label is only
                // shown in the central hub (see below), not here.
                let size = ICON_SIZE_PX + t as f64 * ICON_HOVER_GROW_PX;
                draw_icon(&widget, snapshot, &self.icons.borrow(), seg, px, py, size, t, open);
            }

            // Central hub -- shows the icon + label of the currently
            // hovered sector, an immediate readout of the current choice
            // (like the weapon name centered in a game's wheel).
            if open > 0.02 {
                let hub_path = circle_path(cx, cy, inner_radius);
                snapshot.push_fill(&hub_path, gsk::FillRule::Winding);
                let full = graphene::Rect::new(0.0, 0.0, w as f32, h as f32);
                snapshot.append_color(
                    &gdk::RGBA::new(0.078, 0.078, 0.086, (0.88 * open) as f32),
                    &full,
                );
                snapshot.pop();

                if let Some(seg) = segments.get(hovered) {
                    let hub_accent = color::resolve(seg.accent.as_deref()).rgb;

                    // Colored hub border -- only in the confirmation
                    // sub-menu, and only when hovering "Confirm" (never
                    // "Cancel"): picks up the hovered sector's tint (red by
                    // construction, see `enter_confirm`), a strong visual
                    // signal that a release/click there will run a
                    // destructive action (reboot, poweroff, ...), readable
                    // even without looking at the sectors themselves.
                    let hub_danger = confirming && hovered == CONFIRM_INDEX;
                    if hub_danger {
                        let stroke = gsk::Stroke::new(HUB_BORDER_WIDTH_PX);
                        snapshot.push_stroke(&hub_path, &stroke);
                        snapshot.append_color(
                            &gdk::RGBA::new(hub_accent.0, hub_accent.1, hub_accent.2, open as f32),
                            &full,
                        );
                        snapshot.pop();
                    }

                    let mut hub_label_font = pango::FontDescription::new();
                    hub_label_font.set_absolute_size(HUB_LABEL_FONT_PX * pango::SCALE as f64);
                    let hub_label = widget.create_pango_layout(Some(&seg.label));
                    hub_label.set_font_description(Some(&hub_label_font));
                    // Long device descriptions wrap instead of overflowing
                    // past the hub circle (see HUB_LABEL_MAX_WIDTH_PX) --
                    // WordChar so a single unbreakable long word still wraps
                    // rather than blowing out the width. Center alignment
                    // keeps shorter wrapped lines centered under longer
                    // ones instead of ragged-left.
                    hub_label.set_width((HUB_LABEL_MAX_WIDTH_PX * pango::SCALE as f64) as i32);
                    hub_label.set_wrap(pango::WrapMode::WordChar);
                    hub_label.set_alignment(pango::Alignment::Center);
                    // pixel_size() only returns the tight ink width, NOT
                    // HUB_LABEL_MAX_WIDTH_PX -- for anything narrower than
                    // the wrap box (e.g. "Power" at ~46px in a 190px box)
                    // it silently drops the alignment's internal x-offset
                    // (confirmed via PyGObject: get_pixel_extents() reports
                    // logical_rect.x=72 for "Power" there, which
                    // pixel_size() has no way to surface). Centering on
                    // that tight width instead of the box put most labels
                    // visibly off-center. Fix: center the BOX (the actual
                    // wrap width) on `cx` -- the layout's own center
                    // alignment then centers the ink within that box,
                    // wherever it happens to sit.
                    let (_, lh) = hub_label.pixel_size();

                    // Vertical icon+label block -- fixed nominal icon
                    // height for layout purposes (HUB_ICON_SIZE_PX),
                    // whether the actual rendering is an SVG texture or
                    // (fallback) a Pango glyph of a slightly different
                    // size: it doesn't need to be pixel-perfect for a rare
                    // fallback.
                    const GAP: f64 = 6.0;
                    let block_h = HUB_ICON_SIZE_PX + GAP + lh as f64;
                    let icon_cy = cy - block_h / 2.0 + HUB_ICON_SIZE_PX / 2.0;

                    // Always at full accent (t=1) -- this is the currently
                    // selected sector, not one more animated hover.
                    // Automatically picks up the sector's own tint
                    // (green/yellow/cyan/red/...), same mechanism as the
                    // ring: no special case here.
                    draw_icon(&widget, snapshot, &self.icons.borrow(), seg, cx, icon_cy, HUB_ICON_SIZE_PX, 1.0, open);

                    // Hub label in the same tint as the icon -- consistent
                    // with the ring rather than a fixed neutral white.
                    let label_color = gdk::RGBA::new(hub_accent.0, hub_accent.1, hub_accent.2, open as f32);
                    snapshot.save();
                    snapshot.translate(&graphene::Point::new(
                        (cx - HUB_LABEL_MAX_WIDTH_PX / 2.0) as f32,
                        (cy - block_h / 2.0 + HUB_ICON_SIZE_PX + GAP) as f32,
                    ));
                    snapshot.append_layout(&hub_label, &label_color);
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
) {
    if let Some(pair) = icons.get(&icons::cache_key(seg)) {
        let rect = graphene::Rect::new(
            (cx - size / 2.0) as f32,
            (cy - size / 2.0) as f32,
            size as f32,
            size as f32,
        );
        // "Normal" texture as the base, "accent" texture (already baked in
        // THIS sector's color, see icons::load) crossfaded on top with
        // `t` -- crossfade between two rasters rather than a GPU
        // color-matrix recolor.
        draw_texture(snapshot, &pair.normal, &rect, open);
        if t > 0.001 {
            draw_texture(snapshot, &pair.accent, &rect, open * t as f64);
        }
        return;
    }

    // Text fallback -- synthetic Confirm/Cancel sectors (no associated SVG
    // file, see `enter_confirm`), or a missing/invalid icon (see
    // `icons::load`).
    let accent = color::resolve(seg.accent.as_deref()).rgb;
    let color = text_color(t, open as f32, accent);
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

/// Sampled polygon approximating a ring sector (outer arc, then inner arc
/// in reverse, or a plain vertex at the center if `inner_r` is ~0) -- same
/// technique as `parallelogram_path` in card.rs (PathBuilder +
/// move_to/line_to/close), with a fixed number of points (`ARC_STEPS`)
/// rather than a dedicated arc primitive.
///
/// `angle_left`/`angle_right` are the cut's PURE angles (the imaginary
/// line starting from the center, with no trimming) -- the gap with the
/// neighboring sector is NOT created by trimming these angles (which would
/// make both edges converge to a point exactly at the center, forming an
/// angle between the two neighboring cuts -- the reported flaw). It's
/// created by offsetting each edge PERPENDICULAR to its own imaginary
/// line, by `gap_px / 2` on each side: the two edges bounding a given gap
/// then remain straight lines parallel to each other (parallel to the
/// shared edge's imaginary line), whatever the radius -- exactly the "two
/// parallel lines next to the imaginary line" layout that was asked for,
/// rather than two radii that meet at the center.
fn wedge_path(
    cx: f64,
    cy: f64,
    inner_r: f64,
    outer_r: f64,
    angle_left: f64,
    angle_right: f64,
    gap_px: f64,
) -> gsk::Path {
    let half_gap = (gap_px / 2.0).max(0.0);

    let (a_out_l, r_out_l) = offset_ray(angle_left, outer_r, half_gap);
    let (a_out_r, r_out_r) = offset_ray(angle_right, outer_r, -half_gap);
    let pt = |a: f64, r: f64| (cx + r * a.cos(), cy + r * a.sin());

    let outer: Vec<(f64, f64)> = (0..=ARC_STEPS)
        .map(|step| {
            let t = step as f64 / ARC_STEPS as f64;
            pt(a_out_l + (a_out_r - a_out_l) * t, r_out_l + (r_out_r - r_out_l) * t)
        })
        .collect();

    let has_hub_gap = inner_r > half_gap + 1.0;
    let builder = gsk::PathBuilder::new();

    if !has_hub_gap {
        // No real hub gap -- falls back to the original sharp tip at dead
        // center, same as before. Rounding a single "corner" that's
        // really just a point wouldn't read as anything but a smaller,
        // still-pointed tip, so this case is left alone.
        for (i, &(x, y)) in outer.iter().enumerate() {
            if i == 0 {
                builder.move_to(x as f32, y as f32);
            } else {
                builder.line_to(x as f32, y as f32);
            }
        }
        builder.line_to(cx as f32, cy as f32);
        builder.close();
        return builder.to_path();
    }

    let (a_in_l, r_in_l) = offset_ray(angle_left, inner_r, half_gap);
    let (a_in_r, r_in_r) = offset_ray(angle_right, inner_r, -half_gap);
    let inner: Vec<(f64, f64)> = (0..=ARC_STEPS)
        .map(|step| {
            let t = step as f64 / ARC_STEPS as f64;
            pt(a_in_r + (a_in_l - a_in_r) * t, r_in_r + (r_in_l - r_in_r) * t)
        })
        .collect();

    // The 4 sharp vertices, each rounded off using the already-sampled
    // point one step into its adjacent arc (a close enough tangent
    // approximation at ARC_STEPS resolution) or the opposite vertex
    // across a straight edge -- see round_corner's own doc.
    let outer_left = outer[0];
    let outer_right = outer[ARC_STEPS];
    let inner_right = inner[0];
    let inner_left = inner[ARC_STEPS];

    let emit = |points: Vec<(f64, f64)>, started: &mut bool| {
        for (x, y) in points {
            if *started {
                builder.line_to(x as f32, y as f32);
            } else {
                builder.move_to(x as f32, y as f32);
                *started = true;
            }
        }
    };

    let mut started = false;
    emit(
        round_corner(inner_left, outer_left, outer[1], WEDGE_CORNER_RADIUS, CORNER_STEPS),
        &mut started,
    );
    // Middle of the outer arc, corners already sampled at both ends above.
    for &(x, y) in &outer[1..ARC_STEPS] {
        builder.line_to(x as f32, y as f32);
    }
    emit(
        round_corner(outer[ARC_STEPS - 1], outer_right, inner_right, WEDGE_CORNER_RADIUS, CORNER_STEPS),
        &mut started,
    );
    emit(
        round_corner(outer_right, inner_right, inner[1], WEDGE_CORNER_RADIUS, CORNER_STEPS),
        &mut started,
    );
    for &(x, y) in &inner[1..ARC_STEPS] {
        builder.line_to(x as f32, y as f32);
    }
    emit(
        round_corner(inner[ARC_STEPS - 1], inner_left, outer_left, WEDGE_CORNER_RADIUS, CORNER_STEPS),
        &mut started,
    );
    // close() draws the untouched middle portion of the left edge, from
    // the last point above (near inner_left, on the left edge) back to
    // the very first point (near outer_left, on the same left edge) --
    // same principle as every other straight run between two rounded
    // corners here, just implicit via close() instead of an explicit loop.
    builder.close();
    builder.to_path()
}

/// Replaces a sharp polygon corner with a small rounded fillet, using a
/// quadratic Bézier (the original vertex as control point) between two
/// points backed off along the adjacent edges -- not a true circular arc:
/// much simpler to get right than computing a tangent-fillet center, and
/// at this radius the visual difference is imperceptible. `radius` is
/// clamped to at most half of either adjacent edge's length, so short
/// edges never produce overlapping/self-intersecting fillets.
fn round_corner(
    prev: (f64, f64),
    corner: (f64, f64),
    next: (f64, f64),
    radius: f64,
    steps: usize,
) -> Vec<(f64, f64)> {
    let d_prev = ((corner.0 - prev.0).powi(2) + (corner.1 - prev.1).powi(2)).sqrt();
    let d_next = ((next.0 - corner.0).powi(2) + (next.1 - corner.1).powi(2)).sqrt();
    let r = radius.min(d_prev * 0.5).min(d_next * 0.5).max(0.0);
    if r < 0.5 || d_prev < 0.001 || d_next < 0.001 {
        return vec![corner];
    }
    let a = (
        corner.0 + (prev.0 - corner.0) / d_prev * r,
        corner.1 + (prev.1 - corner.1) / d_prev * r,
    );
    let b = (
        corner.0 + (next.0 - corner.0) / d_next * r,
        corner.1 + (next.1 - corner.1) / d_next * r,
    );
    (0..=steps)
        .map(|i| {
            let t = i as f64 / steps as f64;
            let mt = 1.0 - t;
            (
                mt * mt * a.0 + 2.0 * mt * t * corner.0 + t * t * b.0,
                mt * mt * a.1 + 2.0 * mt * t * corner.1 + t * t * b.1,
            )
        })
        .collect()
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

/// A sector's fill color -- interpolates from neutral gray to a dark shade
/// tinted with `accent` (this sector's RESOLVED color, see
/// `color::resolve` -- cyan by default, green/yellow/red/... if the TOML
/// specifies it) with `t` (hover highlight), never the full accent: stays
/// a sector background, not a solid-color button. `open` multiplies the
/// alpha (fade-in on opening). `MIX` sets the dose of accent blended into
/// the background gray -- a generic formula rather than a per-tint
/// constant, to stay valid whatever the color (see its doc in color.rs):
/// an unbounded number of colors, not just cyan/red.
fn wedge_color(t: f32, open: f32, accent: (f32, f32, f32)) -> gdk::RGBA {
    const MIX: f32 = 0.20;
    let base = (0.145_f32, 0.145, 0.153);
    let k = MIX * t;
    gdk::RGBA::new(
        base.0 + (accent.0 - base.0) * k,
        base.1 + (accent.1 - base.1) * k,
        base.2 + (accent.2 - base.2) * k,
        (0.80 + 0.10 * t) * open,
    )
}

/// A sector's text/icon color -- off-white at rest, full `accent` (this
/// sector's resolved color) once hovered (`t` -> 1).
fn text_color(t: f32, open: f32, accent: (f32, f32, f32)) -> gdk::RGBA {
    let base = (0.949_f32, 0.949, 0.969);
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
    pub fn new(segments: Vec<Segment>) -> Self {
        let wheel: Self = glib::Object::builder().build();
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

    /// Changes the hovered sector to the one pointed at by `(x, y)`
    /// (coordinates relative to the widget, e.g. from an
    /// EventControllerMotion) -- computes the point's angle relative to
    /// the center, like an analog stick. Ignored if the point is too close
    /// to the center (see HOVER_DEADZONE_PX).
    pub fn hover_from_point(&self, x: f64, y: f64) {
        let w = self.width() as f64;
        let h = self.height() as f64;
        if w <= 0.0 || h <= 0.0 {
            return;
        }
        let dx = x - w / 2.0;
        let dy = y - h / 2.0;
        if (dx * dx + dy * dy).sqrt() < HOVER_DEADZONE_PX {
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

    /// Moves the hover by `delta` sectors (keyboard navigation).
    pub fn move_hover(&self, delta: i32) {
        let n = self.imp().segments.borrow().len();
        if n == 0 {
            return;
        }
        let cur = self.imp().hovered.get() as i32;
        let next = (cur + delta).rem_euclid(n as i32) as usize;
        self.set_hover_index(next);
    }

    /// Hovers sector `index` directly (direct keyboard access by digit, or
    /// angle computed from the mouse).
    pub fn set_hover_index(&self, index: usize) {
        let n = self.imp().segments.borrow().len();
        if n == 0 || index >= n {
            return;
        }
        // Marked even if `index` already equals the current hover (e.g.
        // deliberately aiming at sector 0, which is also the default
        // value) -- see `activate_hovered`: this is a real aiming gesture
        // that must count, not just an index CHANGE.
        self.imp().moved.set(true);
        if self.imp().hovered.get() != index {
            self.imp().hovered.set(index);
            self.imp().hover_anim.set(0.0);
            self.queue_draw();
        }
    }

    /// Confirms the currently hovered sector. Returns `true` if the caller
    /// should close the window now (action launched, or cancellation),
    /// `false` if the wheel should stay open (switching to/from the
    /// Confirm/Cancel sub-menu).
    ///
    /// If no aiming has happened since this level opened (root or
    /// sub-menu -- see `moved`), confirming is equivalent to canceling
    /// rather than picking the default sector (index 0): without this
    /// guard, a simple tap of the key that opens the wheel (near-immediate
    /// press+release, mouse not yet repositioned) would ALWAYS run the
    /// first sector -- Lock for the power wheel, so a screen lock on every
    /// brief tap instead of simply showing the wheel.
    pub fn activate_hovered(&self) -> bool {
        let imp = self.imp();
        let moved = imp.moved.get();

        if imp.confirming.get() {
            let confirmed = moved && imp.hovered.get() == CONFIRM_INDEX;
            if confirmed {
                let pending = imp.pending.borrow().clone();
                self.exit_confirm();
                if let Some(seg) = pending {
                    if let Some(cb) = imp.commit_cb.borrow().as_ref() {
                        cb(&seg);
                    }
                }
                true
            } else {
                // Explicit Cancel, OR no movement in the sub-menu -- in
                // both cases return to the root wheel without acting,
                // never a default confirmation.
                self.exit_confirm();
                false
            }
        } else if !moved {
            true
        } else {
            let idx = imp.hovered.get();
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
        // Cancel at CANCEL_INDEX (0), Confirm at CONFIRM_INDEX (1) -- the
        // vec's order IS the index, so Cancel must stay the first element:
        // it's the sub-menu's default selection (sector 0), the least
        // destructive option if the user has no mouse. Confirm picks up
        // `confirm_accent` from the root sector (cyan by default if
        // absent, like `accent` -- see color.rs): this is NO LONGER a
        // hardcoded red, only genuinely destructive sectors
        // (wheels/power.toml) force it explicitly. Cancel keeps `None`
        // (cyan by default), never the confirmed sector's tint.
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
        imp.hovered.set(CANCEL_INDEX);
        imp.hover_anim.set(1.0);
        // Il faut viser À NOUVEAU dans ce sous-menu avant de pouvoir le
        // valider (cf. `activate_hovered`) -- le mouvement fait pour
        // atteindre le secteur `confirm` racine ne compte pas ici.
        imp.moved.set(false);
        self.queue_draw();
    }

    fn exit_confirm(&self) {
        let imp = self.imp();
        imp.confirming.set(false);
        *imp.pending.borrow_mut() = None;
        *imp.segments.borrow_mut() = imp.root_segments.borrow().clone();
        imp.hovered.set(0);
        imp.hover_anim.set(1.0);
        imp.moved.set(false);
        self.queue_draw();
    }
}
