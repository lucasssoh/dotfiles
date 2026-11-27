//! The stack of theme bands under the preview: one band of wallpapers per
//! theme, the current one in the middle. That band is the carousel itself
//! (its cards, focus and clicks); the bands just above and below are drawn
//! here, from the same cards' thumbnails and at the same geometry, faded
//! toward the outside. Changing theme rolls the stack by one band: the
//! carousel takes the new band's cards at once, and the whole stack slides
//! from where that band was, so nothing reloads and nothing jumps.
//!
//! Each band's name sits at the left of its row: the current one lit, the
//! ones above and below readable, with the key that reaches them.

use gtk4::prelude::*;
use gtk4::subclass::prelude::*;
use gtk4::{gdk, glib, graphene, gsk};
use std::cell::{Cell, RefCell};

use crate::card;
use crate::carousel::{self, Carousel};

/// Centre-to-centre distance between two bands.
pub const PITCH: f64 = card::HEIGHT_FOCUSED + 34.0;
/// Same easing as the carousel's (carousel.rs).
const EASE_RATE: f64 = 14.0;
/// The wallpapers fade out under the names on the left, and at the right
/// edge, as shares of the width.
const FADE_LEFT: f32 = 0.17;
const FADE_RIGHT: f32 = 0.06;
/// The names' column, from the left edge, as a share of the width.
const NAMES_X: f64 = 0.024;
const NAMES_MAX: f64 = 0.15;
/// A band past this many pitches from the middle is not drawn.
const REACH: f64 = 1.45;

/// One card of a neighbouring band: `d` slots from that band's focus, with
/// both halves' thumbnails when they are loaded.
pub struct Slot {
    pub d: i64,
    pub light: Option<gdk::Texture>,
    pub dark: Option<gdk::Texture>,
    pub pair: bool,
}

/// The cards of the band `delta` bands from the current one, around its
/// focus; empty when there is no band there.
pub type Provider = Box<dyn Fn(i64) -> Vec<Slot>>;

/// How visible a band is, `n` pitches from the middle: a neighbour at
/// three quarters, fading out beyond.
fn visibility(n: f64) -> f64 {
    if n <= 1.0 {
        1.0 - 0.25 * n
    } else {
        (0.75 * (1.0 - (n - 1.0) / (REACH - 1.0))).max(0.0)
    }
}

mod imp {
    use super::*;

    #[derive(Default)]
    pub struct Roll {
        pub carousel: RefCell<Option<Carousel>>,
        pub titles: RefCell<Vec<gtk4::Widget>>,
        pub current: Cell<usize>,
        /// Where the stack is drawn from, in px: the band that just became
        /// current starts where it was and eases to 0.
        pub offset: Cell<f64>,
        pub last_us: Cell<Option<i64>>,
        pub ticking: Cell<bool>,
        pub provider: RefCell<Option<Provider>>,
        pub dark_scheme: Cell<bool>,
        pub clicked: RefCell<Option<Box<dyn Fn(i64)>>>,
    }

    #[glib::object_subclass]
    impl ObjectSubclass for Roll {
        const NAME: &'static str = "PrismeRoll";
        type Type = super::Roll;
        type ParentType = gtk4::Widget;
    }

    impl ObjectImpl for Roll {
        fn dispose(&self) {
            while let Some(child) = self.obj().first_child() {
                child.unparent();
            }
        }
    }

    impl WidgetImpl for Roll {
        // No size of its own, like the carousel (see Carousel::measure).
        fn measure(&self, _orientation: gtk4::Orientation, _for_size: i32) -> (i32, i32, i32, i32) {
            (0, 0, -1, -1)
        }

        fn size_allocate(&self, width: i32, height: i32, _baseline: i32) {
            if let Some(c) = self.carousel.borrow().as_ref() {
                c.allocate(width, height, -1, None);
            }
            let row_y = height as f64 - carousel::ROW_FROM_BOTTOM_PX;
            let half = card::HEIGHT_FOCUSED / 2.0;
            let current = self.current.get() as i64;
            for (k, title) in self.titles.borrow().iter().enumerate() {
                let d = k as i64 - current;
                if d.abs() > 2 {
                    title.set_child_visible(false);
                    continue;
                }
                title.set_child_visible(true);
                let (_, nat) = title.preferred_size();
                let tw = (nat.width() as f64).min(width as f64 * NAMES_MAX).max(1.0);
                let th = nat.height() as f64;
                let centre = row_y + d as f64 * PITCH;
                // Above and below, the name keeps to the edge facing the
                // middle band: never cut by the panel or the bottom line.
                let y = match d {
                    0 => centre - th / 2.0,
                    d if d < 0 => centre + half - th - 6.0,
                    _ => centre - half + 6.0,
                };
                let x = width as f64 * NAMES_X;
                let t = gsk::Transform::new().translate(&graphene::Point::new(x.round() as f32, y.round() as f32));
                title.allocate(tw.round() as i32, th.round() as i32, -1, Some(t));
            }
        }

        fn snapshot(&self, snapshot: &gtk4::Snapshot) {
            let widget = self.obj();
            let (w, h) = (widget.width() as f32, widget.height() as f32);
            if w <= 0.0 || h <= 0.0 {
                return;
            }
            let row_y = h as f64 - carousel::ROW_FROM_BOTTOM_PX;
            let offset = self.offset.get();
            let half = (card::HEIGHT_FOCUSED / 2.0) as f32 + 14.0;

            // The wallpapers, under a horizontal fade.
            snapshot.push_mask(gsk::MaskMode::Alpha);
            let clear = gdk::RGBA::new(0.0, 0.0, 0.0, 0.0);
            let solid = gdk::RGBA::new(0.0, 0.0, 0.0, 1.0);
            snapshot.append_linear_gradient(
                &graphene::Rect::new(0.0, 0.0, w, h),
                &graphene::Point::new(0.0, 0.0),
                &graphene::Point::new(w, 0.0),
                &[
                    gsk::ColorStop::new(0.0, clear),
                    gsk::ColorStop::new(FADE_LEFT, solid),
                    gsk::ColorStop::new(1.0 - FADE_RIGHT, solid),
                    gsk::ColorStop::new(1.0, clear),
                ],
            );
            snapshot.pop();
            for d in -2i64..=2 {
                let shift = d as f64 * PITCH + offset;
                let n = shift.abs() / PITCH;
                let seen = visibility(n);
                if seen <= 0.001 {
                    continue;
                }
                let y = (row_y + shift) as f32;
                snapshot.push_opacity(seen);
                // Toward the outside, the band fades out: from its inner
                // edge to nothing at its outer one, not at all in the middle.
                let s = n.min(1.0) as f32;
                let (from, to) = if shift < 0.0 { (y - half, y + half) } else { (y + half, y - half) };
                snapshot.push_mask(gsk::MaskMode::Alpha);
                snapshot.append_linear_gradient(
                    &graphene::Rect::new(0.0, y - half, w, 2.0 * half),
                    &graphene::Point::new(0.0, from),
                    &graphene::Point::new(0.0, to),
                    &[
                        gsk::ColorStop::new(0.0, gdk::RGBA::new(0.0, 0.0, 0.0, 1.0 - s)),
                        gsk::ColorStop::new(1.0, solid),
                    ],
                );
                snapshot.pop();
                snapshot.save();
                snapshot.translate(&graphene::Point::new(0.0, shift as f32));
                if d == 0 {
                    if let Some(c) = self.carousel.borrow().as_ref() {
                        widget.snapshot_child(c, snapshot);
                    }
                } else {
                    self.draw_band(snapshot, d, w as f64, row_y);
                }
                snapshot.restore();
                snapshot.pop();
                snapshot.pop();
            }
            snapshot.pop();

            // The names, over the fade.
            let current = self.current.get() as i64;
            for (k, title) in self.titles.borrow().iter().enumerate() {
                let d = k as i64 - current;
                if d.abs() > 2 {
                    continue;
                }
                let shift = d as f64 * PITCH + offset;
                let seen = if d == 0 { 1.0 } else { visibility(shift.abs() / PITCH).min(1.0) };
                if seen <= 0.001 {
                    continue;
                }
                snapshot.push_opacity(seen);
                snapshot.save();
                snapshot.translate(&graphene::Point::new(0.0, offset as f32));
                widget.snapshot_child(title, snapshot);
                snapshot.restore();
                snapshot.pop();
            }
        }
    }

    impl Roll {
        /// A neighbouring band at rest, as the carousel would lay it out
        /// with no motion: the focused card wide, the others slices.
        fn draw_band(&self, snapshot: &gtk4::Snapshot, delta: i64, width: f64, row_y: f64) {
            let slots = match self.provider.borrow().as_ref() {
                Some(p) => p(delta),
                None => return,
            };
            let step = card::WIDTH_UNFOCUSED + carousel::CARD_GAP_PX;
            let extra = (card::WIDTH_FOCUSED - card::WIDTH_UNFOCUSED) / 2.0;
            let cx = width / 2.0;
            let h = card::HEIGHT_FOCUSED;
            let dark = self.dark_scheme.get();
            for slot in slots {
                let d = slot.d as f64;
                let w = if slot.d == 0 { card::WIDTH_FOCUSED } else { card::WIDTH_UNFOCUSED };
                let x_center = cx + d * step + d.signum() * d.abs().min(1.0) * extra;
                if x_center + w / 2.0 < 0.0 || x_center - w / 2.0 > width {
                    continue;
                }
                snapshot.save();
                snapshot.translate(&graphene::Point::new((x_center - w / 2.0).round() as f32, (row_y - h / 2.0).round() as f32));
                let focus = if slot.d == 0 { 1.0 } else { 0.0 };
                card::paint(
                    snapshot,
                    w as f32,
                    h as f32,
                    slot.light.as_ref(),
                    slot.dark.as_ref(),
                    slot.pair,
                    dark,
                    if dark { 1.0 } else { 0.0 },
                    focus,
                );
                snapshot.restore();
            }
        }

        pub(super) fn tick(&self, clock: &gdk::FrameClock) -> glib::ControlFlow {
            let now = clock.frame_time();
            let dt = self.last_us.get().map(|p| ((now - p).max(0) as f64 / 1e6).min(0.1)).unwrap_or(1.0 / 60.0);
            self.last_us.set(Some(now));
            let next = self.offset.get() * (-EASE_RATE * dt).exp();
            self.obj().queue_draw();
            if next.abs() < 0.5 {
                self.offset.set(0.0);
                self.ticking.set(false);
                self.last_us.set(None);
                return glib::ControlFlow::Break;
            }
            self.offset.set(next);
            glib::ControlFlow::Continue
        }
    }
}

glib::wrapper! {
    pub struct Roll(ObjectSubclass<imp::Roll>) @extends gtk4::Widget;
}

impl Roll {
    /// The stack around `carousel`, with one name widget per band, in
    /// band order.
    pub fn new(carousel: &Carousel, titles: Vec<gtk4::Widget>) -> Self {
        let roll: Self = glib::Object::builder().build();
        roll.set_hexpand(true);
        roll.set_vexpand(true);
        carousel.set_parent(&roll);
        for t in &titles {
            t.set_parent(&roll);
        }
        *roll.imp().carousel.borrow_mut() = Some(carousel.clone());
        *roll.imp().titles.borrow_mut() = titles;

        // A click on a neighbouring band, or on its name, rolls to it.
        let click = gtk4::GestureClick::new();
        let weak = roll.downgrade();
        click.connect_released(move |_, _, _, y| {
            let Some(roll) = weak.upgrade() else {
                return;
            };
            let row_y = roll.height() as f64 - carousel::ROW_FROM_BOTTOM_PX;
            let d = ((y - row_y) / PITCH).round() as i64;
            if d.abs() == 1 {
                if let Some(cb) = roll.imp().clicked.borrow().as_ref() {
                    cb(d);
                }
            }
        });
        roll.add_controller(click);
        roll
    }

    /// Where the neighbouring bands' cards come from (main.rs).
    pub fn set_provider(&self, provider: Provider) {
        *self.imp().provider.borrow_mut() = Some(provider);
    }

    pub fn connect_clicked(&self, f: impl Fn(i64) + 'static) {
        *self.imp().clicked.borrow_mut() = Some(Box::new(f));
    }

    /// The desktop's scheme: which half of a pair the bands show.
    pub fn set_dark_scheme(&self, dark: bool) {
        self.imp().dark_scheme.set(dark);
        self.queue_draw();
    }

    /// Makes band `i` the middle one; with `roll`, the stack slides there
    /// from where that band was.
    pub fn set_current(&self, i: usize, roll: bool) {
        let imp = self.imp();
        let previous = imp.current.replace(i);
        if roll && previous != i {
            imp.offset.set(imp.offset.get() + (i as f64 - previous as f64) * PITCH);
            if !imp.ticking.replace(true) {
                self.add_tick_callback(|roll, clock| roll.imp().tick(clock));
            }
        }
        self.queue_allocate();
        self.queue_draw();
    }
}
