//! `RoueWheel` widget: the radial selection wheel itself (drawing,
//! mouse/keyboard aim, animation, confirmation). Generic over the list of
//! sectors received at construction -- no knowledge of "power" or
//! "powerprofile" here, this is what allows this widget to be reused as-is
//! for any future wheel (see config.rs).
//!
//! Drawn entirely in GSK: one glass pastille per sector on a dotted
//! circle, the aimed one inverted (DrawerTheme's `on`, like a control-
//! centre button), and the aimed sector's name -- or the wheel's own,
//! while nothing is aimed -- bare in the middle, over the blurred desktop
//! (style.css). Paths are sampled point by point (gsk::PathBuilder has no
//! arc primitive in this version). It was a black disc with a grey track
//! and an arc on the hovered sector before the glass drawers.

use gtk4::glib;
use gtk4::prelude::*;
use gtk4::subclass::prelude::*;
use gtk4::{gdk, graphene, gsk, pango};
use std::cell::{Cell, RefCell};
use std::collections::HashMap;

use crate::config::Segment;
use crate::icons::{self, IconPair};
use crate::palette::{Palette, Rgba};

/// Convergence speed of the exponential interpolation (opening + aim) --
/// ~220ms to converge at 95%, independent of refresh rate thanks to the
/// frame clock's real dt.
const EASE_RATE: f64 = 14.0;

const WHEEL_SIZE_PX: i32 = 520;
/// Radius of the circle the pastilles' centres sit on.
const RING_RADIUS_PX: f64 = 176.0;
const PILL_RADIUS_PX: f64 = 40.0;
/// How much the aimed pastille grows.
const PILL_GROW_PX: f64 = 4.0;
const ICON_SIZE_PX: f64 = 26.0;
const ICON_GROW_PX: f64 = 2.0;
/// The dot marking the applied state (the TOML's `active`), outside its
/// pastille.
const STATE_DOT_RADIUS_PX: f64 = 3.0;
const STATE_DOT_OFFSET_PX: f64 = 14.0;
/// The dotted circle stops this far short of each pastille's edge.
const GUIDE_GAP_PX: f64 = 8.0;
/// The scale the wheel opens from.
const OPEN_FROM_SCALE: f64 = 0.82;
/// Radius (px) around the center where mouse aim is ignored -- avoids an
/// angle that jumps erratically when the cursor passes very close to the
/// center (atan2(0,0) isn't stably defined), same role as an analog
/// joystick's dead zone.
const HOVER_DEADZONE_PX: f64 = 28.0;
const ARC_STEPS: usize = 24;
/// The name in the middle: the aimed sector's, or the wheel's at rest.
const LABEL_FONT_PX: f64 = 26.0;
const TITLE_FONT_PX: f64 = 22.0;
/// Wrap width of that name -- comfortably inside the pastilles' inner
/// edge (RING_RADIUS_PX - PILL_RADIUS_PX = 136px from the centre).
const LABEL_MAX_WIDTH_PX: f64 = 220.0;
/// Index of Confirm among the confirmation sub-menu's two synthetic
/// sectors (see `enter_confirm`): Cancel on top, Confirm below.
const CONFIRM_INDEX: usize = 1;

mod imp {
    use super::*;

    #[derive(Default)]
    pub struct Wheel {
        /// Root wheel sectors, never modified after construction -- used to
        /// go back when leaving the confirmation sub-menu (see
        /// `Wheel::exit_confirm`).
        pub root_segments: RefCell<Vec<Segment>>,
        /// Sectors actually displayed/aimed at -- identical to
        /// `root_segments`, except during a confirmation where they
        /// temporarily hold [Cancel, Confirm].
        pub segments: RefCell<Vec<Segment>>,
        /// Textures rasterized once at construction (see `RoueWheel::new`),
        /// by icon file name -- Cancel's and Confirm's included.
        pub icons: RefCell<HashMap<String, IconPair>>,
        pub palette: Cell<Option<Palette>>,
        /// Index (in `root_segments`) of the sector marked `active = true`
        /// in the TOML, if any -- computed once at construction, never
        /// afterwards (the script that writes the TOML regenerates it on
        /// every opening). Ignored during a confirmation.
        pub active_index: Cell<Option<usize>>,
        /// The aimed sector, None until something aims (the mouse past the
        /// dead zone, a click, an arrow, a digit) on this level of the
        /// wheel (root or confirmation sub-menu). Nothing is drawn as
        /// selected before that, so what is lit is always what Enter or a
        /// click would run.
        pub hovered: Cell<Option<usize>>,
        /// The sector aimed at just before, fading out as `hover_anim`
        /// brings the new one in.
        pub prev_hovered: Cell<Option<usize>>,
        /// The wheel's name, shown in the middle while nothing is aimed.
        pub title: RefCell<String>,
        /// Last pointer position seen, in the widget's frame.
        pub last_pointer: Cell<Option<(f64, f64)>>,
        /// Where the pointer was when the confirmation sub-menu opened. A
        /// click there does not aim: it is the second click of a double
        /// click on a destructive sector, which would otherwise land on
        /// Confirm whenever that sector sits in the lower half. Cleared
        /// once the pointer moves away.
        pub confirm_anchor: Cell<Option<(f64, f64)>>,
        /// 0 = closed, 1 = fully open -- scales and fades everything drawn.
        pub open_progress: Cell<f64>,
        /// 0 = aimed pastille not yet inverted, 1 = fully -- back to 0 on
        /// every change of aim (see `set_hover_index`).
        pub hover_anim: Cell<f64>,
        pub confirming: Cell<bool>,
        pub pending: RefCell<Option<Segment>>,
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
        // Fixed, constant size: only what's drawn inside animates.
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
            let Some(pal) = self.palette.get() else { return };
            if n == 0 {
                return;
            }

            let open = self.open_progress.get();
            if open <= 0.01 {
                return;
            }
            let scale = OPEN_FROM_SCALE + (1.0 - OPEN_FROM_SCALE) * open;
            let cx = w / 2.0;
            let cy = h / 2.0;
            let ring = RING_RADIUS_PX * scale;
            let full = graphene::Rect::new(0.0, 0.0, w as f32, h as f32);

            let angle_per = std::f64::consts::TAU / n as f64;
            let base = -std::f64::consts::FRAC_PI_2 - angle_per / 2.0;
            let mid = |i: usize| base + (i as f64 + 0.5) * angle_per;
            let hovered = self.hovered.get();
            let prev = self.prev_hovered.get();
            let hover_t = self.hover_anim.get();
            let confirming = self.confirming.get();
            let active_index = if confirming { None } else { self.active_index.get() };
            let danger_confirm = confirming
                && self.pending.borrow().as_ref().is_some_and(|p| p.confirm_accent.is_some());

            // The dotted circle, broken around each pastille: it shows
            // through the pastilles' veil otherwise.
            let gap = ((PILL_RADIUS_PX + GUIDE_GAP_PX) * scale / ring).min(1.0).asin();
            if angle_per > 2.0 * gap {
                let dash = gsk::Stroke::new(1.2);
                dash.set_line_cap(gsk::LineCap::Round);
                dash.set_dash(&[0.01, 7.0]);
                for i in 0..n {
                    let a0 = mid(i) + gap;
                    let a1 = mid(i) + angle_per - gap;
                    snapshot.push_stroke(&arc_path(cx, cy, ring, a0, a1), &dash);
                    snapshot.append_color(&rgba(pal.guide, open), &full);
                    snapshot.pop();
                }
            }

            for (i, seg) in segments.iter().enumerate() {
                // How inverted this pastille is: rising on the aimed one,
                // falling on the one just left.
                let t = if Some(i) == hovered {
                    hover_t
                } else if Some(i) == prev {
                    1.0 - hover_t
                } else {
                    0.0
                };
                let a = mid(i);
                let px = cx + ring * a.cos();
                let py = cy + ring * a.sin();
                let r = (PILL_RADIUS_PX + PILL_GROW_PX * t) * scale;
                let pill = circle_path(px, py, r);

                // The glass at rest: veil, rim, a light along the top.
                if t < 0.999 {
                    let rest = 1.0 - t;
                    snapshot.push_fill(&pill, gsk::FillRule::Winding);
                    snapshot.append_color(&rgba(pal.pill, open * rest), &full);
                    snapshot.pop();
                    snapshot.push_stroke(&pill, &gsk::Stroke::new(1.0));
                    snapshot.append_color(&rgba(pal.rim, open * rest), &full);
                    snapshot.pop();
                    let top = gsk::Stroke::new(1.2);
                    top.set_line_cap(gsk::LineCap::Round);
                    let up = -std::f64::consts::FRAC_PI_2;
                    snapshot.push_stroke(&arc_path(px, py, r - 1.0, up - 0.9, up + 0.9), &top);
                    snapshot.append_color(&rgba(pal.highlight, open * rest), &full);
                    snapshot.pop();
                }
                // The inversion. Red only for a destructive Confirm.
                if t > 0.001 {
                    let fill = if confirming && i == CONFIRM_INDEX && danger_confirm { pal.danger } else { pal.on };
                    snapshot.push_fill(&pill, gsk::FillRule::Winding);
                    snapshot.append_color(&rgba(fill, open * t), &full);
                    snapshot.pop();
                }

                let size = (ICON_SIZE_PX + ICON_GROW_PX * t) * scale;
                if let Some(pair) = self.icons.borrow().get(&seg.icon) {
                    let rect = graphene::Rect::new(
                        (px - size / 2.0) as f32,
                        (py - size / 2.0) as f32,
                        size as f32,
                        size as f32,
                    );
                    draw_texture(snapshot, &pair.rest, &rect, open * (1.0 - t));
                    draw_texture(snapshot, &pair.on, &rect, open * t);
                }

                if active_index == Some(i) {
                    let d = ring + (PILL_RADIUS_PX + STATE_DOT_OFFSET_PX) * scale;
                    let dot = circle_path(cx + d * a.cos(), cy + d * a.sin(), STATE_DOT_RADIUS_PX);
                    snapshot.push_fill(&dot, gsk::FillRule::Winding);
                    snapshot.append_color(&rgba(pal.primary, open), &full);
                    snapshot.pop();
                }
            }

            // The middle: the aimed sector's name; at rest the wheel's
            // name, or the question on a confirmation.
            let pending = self.pending.borrow().as_ref().map(|p| format!("{}?", p.label));
            let (text, ink, px, weight) = match hovered.and_then(|h| segments.get(h).map(|s| (h, s))) {
                Some((h, _)) if confirming && h == CONFIRM_INDEX => (
                    pending.clone().unwrap_or_default(),
                    if danger_confirm { pal.danger } else { pal.primary },
                    LABEL_FONT_PX,
                    pango::Weight::Semibold,
                ),
                Some((_, s)) => (s.label.clone(), pal.primary, LABEL_FONT_PX, pango::Weight::Semibold),
                None => (
                    if confirming { pending.unwrap_or_default() } else { self.title.borrow().clone() },
                    pal.secondary,
                    TITLE_FONT_PX,
                    pango::Weight::Medium,
                ),
            };
            let mut font = pango::FontDescription::new();
            font.set_absolute_size(px * pango::SCALE as f64);
            font.set_weight(weight);
            let layout = widget.create_pango_layout(Some(&text));
            layout.set_font_description(Some(&font));
            // The BOX is centred on `cx` and the layout centres the ink in
            // it -- pixel_size() only reports the tight ink width.
            layout.set_width((LABEL_MAX_WIDTH_PX * pango::SCALE as f64) as i32);
            layout.set_wrap(pango::WrapMode::WordChar);
            layout.set_alignment(pango::Alignment::Center);
            let (_, th) = layout.pixel_size();
            snapshot.save();
            snapshot.translate(&graphene::Point::new(
                (cx - LABEL_MAX_WIDTH_PX / 2.0) as f32,
                (cy - th as f64 / 2.0) as f32,
            ));
            snapshot.append_layout(&layout, &rgba(ink, open));
            snapshot.restore();
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

            let op = self.open_progress.get();
            let ha = self.hover_anim.get();
            let op_moving = (1.0 - op).abs() > 0.0005;
            let ha_moving = (1.0 - ha).abs() > 0.0005;
            // Nothing to animate: no frame requested (near-zero cost once
            // settled).
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

fn rgba(c: Rgba, alpha: f64) -> gdk::RGBA {
    gdk::RGBA::new(c.0, c.1, c.2, c.3 * alpha as f32)
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

/// An open arc of radius `r` from angle `a0` to `a1` (radians, a1 > a0).
fn arc_path(cx: f64, cy: f64, r: f64, a0: f64, a1: f64) -> gsk::Path {
    let builder = gsk::PathBuilder::new();
    for step in 0..=ARC_STEPS {
        let a = a0 + (a1 - a0) * step as f64 / ARC_STEPS as f64;
        let (x, y) = ((cx + r * a.cos()) as f32, (cy + r * a.sin()) as f32);
        if step == 0 {
            builder.move_to(x, y);
        } else {
            builder.line_to(x, y);
        }
    }
    builder.to_path()
}

fn circle_path(cx: f64, cy: f64, r: f64) -> gsk::Path {
    let builder = gsk::PathBuilder::new();
    builder.add_circle(&graphene::Point::new(cx as f32, cy as f32), r as f32);
    builder.to_path()
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
    pub fn new(title: &str, segments: Vec<Segment>, palette: Palette) -> Self {
        let wheel: Self = glib::Object::builder().build();
        let imp = wheel.imp();
        *imp.title.borrow_mut() = title.to_string();
        imp.palette.set(Some(palette));
        *imp.icons.borrow_mut() = icons::load(&segments, &palette);
        // At most one `active = true` sector; the first one wins.
        imp.active_index.set(segments.iter().position(|s| s.active));
        *imp.root_segments.borrow_mut() = segments.clone();
        *imp.segments.borrow_mut() = segments;

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
            self.imp().prev_hovered.set(self.imp().hovered.get());
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
        imp.confirming.set(true);
        // Whether Confirm turns red is read from the pending sector itself
        // (its `confirm_accent`, see snapshot()).
        *imp.pending.borrow_mut() = Some(seg);
        let synthetic = |icon: &str, label: &str| Segment {
            icon: icon.into(),
            label: label.into(),
            action: String::new(),
            confirm: false,
            confirm_accent: None,
            active: false,
        };
        // Cancel first (top half), Confirm second (bottom half).
        *imp.segments.borrow_mut() = vec![
            synthetic(icons::CANCEL_ICON, "Cancel"),
            synthetic(icons::CONFIRM_ICON, "Confirm"),
        ];
        // Nothing aimed: the sub-menu has to be aimed at again, the
        // gesture that reached the root sector does not count here.
        imp.hovered.set(None);
        imp.prev_hovered.set(None);
        imp.confirm_anchor.set(imp.last_pointer.get());
        self.queue_draw();
    }

    fn exit_confirm(&self) {
        let imp = self.imp();
        imp.confirming.set(false);
        *imp.pending.borrow_mut() = None;
        *imp.segments.borrow_mut() = imp.root_segments.borrow().clone();
        imp.hovered.set(None);
        imp.prev_hovered.set(None);
        imp.confirm_anchor.set(None);
        self.queue_draw();
    }
}
