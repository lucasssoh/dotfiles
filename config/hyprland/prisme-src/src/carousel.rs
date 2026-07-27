//! Wallpaper card carousel: handles circular navigation (scroll, click,
//! keyboard via main.rs), scroll animation via exponential interpolation,
//! and the cascade entrance at launch. Custom widget rather than a
//! standard layout manager, since each card's position, width, and height
//! change continuously — see the comment on `Carousel` below for the full
//! context.

use gtk4::glib;
use gtk4::prelude::*;
use gtk4::subclass::prelude::*;
use gtk4::{gdk, graphene, gsk};
use std::cell::{Cell, RefCell};
use std::time::Instant;

use crate::card::{self, Card};

/// Convergence speed of the exponential interpolation of the animated
/// offset toward its target (higher = faster) -- ~14 converges to ~95% in
/// ~220ms, giving the feel of a damped spring without computing one
/// explicitly. Independent of screen refresh rate: `tick()` uses the frame
/// clock's real dt (180Hz here), so the animation keeps the same perceived
/// duration at 60 as at 180Hz -- only its smoothness changes.
const EASE_RATE: f64 = 14.0;

const CASCADE_STAGGER_MS: f64 = 40.0;
const CASCADE_DURATION_MS: f64 = 320.0;

/// Margin (px) between the bottom of the row (tallest possible card, focus
/// + selection) and the bottom of the allocated area -- the row is
/// bottom-centered (not screen-centered) to leave most of the screen
/// visible behind the overlay while navigating.
const BOTTOM_MARGIN_PX: f64 = 24.0;

/// Extra height (px) for a selected card (Dynamic mode) -- added on top of
/// the focus interpolation, so chosen cards visibly "stick out" of the row
/// even when unfocused.
const SELECTED_HEIGHT_BOOST: f64 = 26.0;

/// Unsigned distance on the ring between two positions (the shorter of the
/// two possible paths) -- used for the cascade entrance (`tick`) and by
/// main.rs for thumbnail loading order, so the two agree on the same
/// notion of "close to the starting point".
pub(crate) fn ring_distance(i: f64, origin: f64, len: f64) -> f64 {
    if len <= 0.0 {
        return 0.0;
    }
    let raw = (i - origin).rem_euclid(len);
    raw.min(len - raw)
}

mod imp {
    use super::*;

    #[derive(Default)]
    pub struct Carousel {
        pub entries: RefCell<Vec<Card>>,
        /// "Logical" position targeted on the ring -- an UNBOUNDED float
        /// (never wrapped here). ± N per full loop, so always monotonically
        /// increasing/decreasing with navigation: this is what allows
        /// infinite scrolling without ever having to decide a rewind
        /// direction.
        pub target: Cell<f64>,
        /// Animated position, converges toward `target` via exponential
        /// interpolation. Wrapping only happens at draw time (per-card
        /// distance, see `size_allocate`), never on these two values --
        /// that avoids any direction ambiguity when crossing from the last
        /// to the first element.
        pub offset: Cell<f64>,
        /// Starting index of the cascade entrance animation -- fixed once
        /// and for all by `set_focus_index` (0 by default), never updated
        /// afterward. Unlike `target`/`offset`, this point must NOT follow
        /// scrolling: if the distance were recomputed every frame from the
        /// current focus, scrolling during the first second would
        /// "un-reveal" cards that had already appeared (their delay would
        /// shift under their feet).
        pub reveal_origin: Cell<f64>,
        pub scroll_accum: Cell<f64>,
        pub start: Cell<Option<Instant>>,
        pub last_frame_us: Cell<Option<i64>>,
        pub activate_cb: RefCell<Option<Box<dyn Fn(usize)>>>,
        /// Called on every INTERACTIVE change of `target` (click, scroll,
        /// keyboard -- see `Carousel::set_target`), with the resulting
        /// focus index -- NOT during `set_focus_index` (initial
        /// positioning, handled separately by the caller, see main.rs).
        /// Used for windowed thumbnail loading/unloading.
        pub target_changed_cb: RefCell<Option<Box<dyn Fn(usize)>>>,
    }

    #[glib::object_subclass]
    impl ObjectSubclass for Carousel {
        const NAME: &'static str = "PrismeCarousel";
        type Type = super::Carousel;
        type ParentType = gtk4::Widget;
    }

    impl ObjectImpl for Carousel {
        fn dispose(&self) {
            for card in self.entries.borrow_mut().drain(..) {
                card.unparent();
            }
        }
    }

    impl WidgetImpl for Carousel {
        // Like Card::measure: no size of its own, so as never to bubble a
        // constraint up to the layer-shell window -- this is the bug that
        // inflated the surface to 3300px on a 2560px screen with the old
        // GtkFixed (measure() returned the union of children's absolute
        // coordinates there, regardless of Overflow::Hidden).
        fn measure(&self, _orientation: gtk4::Orientation, _for_size: i32) -> (i32, i32, i32, i32) {
            (0, 0, -1, -1)
        }

        // Repositions every card from the size actually allocated by the
        // parent (so never circular) -- called every frame via
        // `queue_allocate()` in `tick()`, not just on resize.
        fn size_allocate(&self, width: i32, height: i32, _baseline: i32) {
            let entries = self.entries.borrow();
            let len = entries.len();
            if len == 0 {
                return;
            }
            let width = width as f64;
            let height = height as f64;
            let len_f = len as f64;
            let offset = self.offset.get();
            // Two parallelograms of the same width AND same height,
            // offset by exactly (width - skew), have their slanted edges
            // coincide exactly (verified geometrically on the 4 corners)
            // -- resting value (non-focused, non-selected cards) taken as
            // the reference for spacing.
            let step = card::WIDTH_UNFOCUSED
                - card::skew_for(card::WIDTH_UNFOCUSED, card::HEIGHT_UNFOCUSED);
            // Extra gap to push onto the neighbors when the focused card
            // grows -- NOT just half the width gain: since the slope is
            // proportional to height (card::SKEW_RATIO), a card that also
            // grows in height "eats into" part of that gap with its more
            // slanted edge. Proof: two neighboring edges have exactly the
            // same slope (skew_i/h_i = SKEW_RATIO for every card i), so the
            // gap between them is CONSTANT over their whole shared height
            // (the two lines are parallel) and equals
            // (w_i+w_j)/2 - SKEW_RATIO·(h_i+h_j)/2 -- hence this term in
            // BOTH width and height, not width alone as a v1 of this
            // calculation did (it left a thin visible gap near the focus,
            // where the card is also noticeably taller).
            let extra_reach = (card::WIDTH_FOCUSED - card::WIDTH_UNFOCUSED) / 2.0
                - card::SKEW_RATIO * (card::HEIGHT_FOCUSED - card::HEIGHT_UNFOCUSED) / 2.0;
            let cx = width / 2.0;
            // Shared vertical center of the row, chosen so that even the
            // tallest possible card (focus + selection combined) never
            // exceeds BOTTOM_MARGIN_PX from the bottom -- each card then
            // grows equally up AND down from this line (rather than a
            // bottom anchor that would make everything climb from one
            // side only, breaking the coincidence of slanted edges with
            // neighbors of different height).
            let max_h = card::HEIGHT_FOCUSED + SELECTED_HEIGHT_BOOST;
            let row_center_y = height - BOTTOM_MARGIN_PX - max_h / 2.0;
            let visible_margin = card::WIDTH_FOCUSED + 40.0;

            for (i, card) in entries.iter().enumerate() {
                // Signed distance on the ring, wrapped into [-N/2, N/2) --
                // the only place wrapping happens (see `target`'s doc in
                // Inner). Stays continuous during the animation since
                // `offset` is.
                let mut d = (i as f64 - offset) % len_f;
                if d > len_f / 2.0 {
                    d -= len_f;
                } else if d < -len_f / 2.0 {
                    d += len_f;
                }

                let focus_amount = (1.0 - d.abs()).max(0.0);
                card.set_focus(focus_amount);

                let w = card::WIDTH_UNFOCUSED
                    + (card::WIDTH_FOCUSED - card::WIDTH_UNFOCUSED) * focus_amount;
                let mut h = card::HEIGHT_UNFOCUSED
                    + (card::HEIGHT_FOCUSED - card::HEIGHT_UNFOCUSED) * focus_amount;
                if card.is_selected() {
                    h += SELECTED_HEIGHT_BOOST;
                }

                let sign = d.signum();
                // The focused card (d≈0) is exactly centered by
                // construction: at d=0, this term vanishes.
                let x_center = cx + d * step + sign * d.abs().min(1.0) * extra_reach;

                if x_center + w / 2.0 < -visible_margin
                    || x_center - w / 2.0 > width + visible_margin
                {
                    card.set_child_visible(false);
                    continue;
                }
                card.set_child_visible(true);

                let x = (x_center - w / 2.0).round() as f32;
                let y = (row_center_y - h / 2.0).round() as f32;
                let transform = gsk::Transform::new().translate(&graphene::Point::new(x, y));
                card.allocate(w.round() as i32, h.round() as i32, -1, Some(transform));
            }
        }
    }

    impl Carousel {
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
            let elapsed_ms = self.start.get().unwrap().elapsed().as_secs_f64() * 1000.0;
            let len_f = self.entries.borrow().len() as f64;
            // Farthest possible point on the ring from the cascade's
            // start -- past its delay + duration, no card can still change
            // its reveal value.
            let cascade_running =
                elapsed_ms < (len_f / 2.0).floor() * CASCADE_STAGGER_MS + CASCADE_DURATION_MS;
            let target = self.target.get();
            let offset = self.offset.get();
            let still_easing = (target - offset).abs() > 0.0005;

            // Nothing to animate -- touches nothing and, above all, does
            // not request another frame via queue_allocate(). Measured at
            // ~65% of a core continuously (relayout + redraw of ~25 cards
            // 120-180 times a second) before this guard, while nothing
            // moves on screen; near zero after. Non-animation changes
            // (selection, see main.rs) request an allocate themselves the
            // moment they happen, so nothing ever gets stuck stale by
            // mistake.
            if !still_easing && !cascade_running {
                return;
            }

            let ease = 1.0 - (-EASE_RATE * dt).exp();
            let next = offset + (target - offset) * ease;
            self.offset
                .set(if (next - target).abs() < 0.0005 { target } else { next });

            let entries = self.entries.borrow();
            let origin = self.reveal_origin.get();
            for (i, card) in entries.iter().enumerate() {
                // Distance on the ring from the starting point (not the
                // raw index) -- the cascade entrance starts from the
                // initially focused card and spills toward both sides at
                // once, rather than a simple left→right sweep.
                let dist = ring_distance(i as f64, origin, len_f);
                let delay = dist * CASCADE_STAGGER_MS;
                let t = ((elapsed_ms - delay) / CASCADE_DURATION_MS).clamp(0.0, 1.0);
                let eased = 1.0 - (1.0 - t).powi(3);
                card.set_reveal(eased);
            }

            // Re-triggers size_allocate on the next frame clock pass, with
            // the new `offset` -- never queue_resize (see measure()).
            self.obj().queue_allocate();
        }
    }
}

glib::wrapper! {
    /// The carousel: a `gtk4::Widget` container that recomputes each
    /// card's position/width/height itself every frame -- necessary since
    /// these values animate continuously (focus, cascade entrance,
    /// scrolling), which no standard layout manager natively allows
    /// without reimplementing, precisely, a full layout manager. Replaces
    /// the first version's `GtkFixed`, whose `measure()` bubbled children's
    /// absolute coordinates up to the layer-shell window.
    pub struct Carousel(ObjectSubclass<imp::Carousel>) @extends gtk4::Widget;
}

impl Carousel {
    /// Builds the carousel and parents all the given cards, wiring up
    /// click, scroll/trackpad, and the animation loop.
    pub fn new(cards: Vec<Card>) -> Self {
        let carousel: Self = glib::Object::builder().build();
        carousel.set_overflow(gtk4::Overflow::Hidden);
        carousel.set_hexpand(true);
        carousel.set_vexpand(true);

        {
            let mut entries = carousel.imp().entries.borrow_mut();
            for (index, card) in cards.into_iter().enumerate() {
                card.set_parent(&carousel);

                // Click: selects the targeted card (moves focus along the
                // shortest path on the ring), or activates it if it
                // already had focus.
                let click = gtk4::GestureClick::new();
                let carousel_weak = carousel.downgrade();
                click.connect_pressed(move |_, _, _, _| {
                    if let Some(carousel) = carousel_weak.upgrade() {
                        carousel.handle_card_click(index);
                    }
                });
                card.add_controller(click);

                entries.push(card);
            }
        }

        // Scroll / trackpad -- an accumulator rather than a fixed step per
        // event: a trackpad gesture (many small deltas) advances
        // continuously, one physical wheel notch (delta ≈ ±1) advances
        // immediately by one card.
        let scroll =
            gtk4::EventControllerScroll::new(gtk4::EventControllerScrollFlags::BOTH_AXES);
        {
            let carousel_weak = carousel.downgrade();
            scroll.connect_scroll(move |_, dx, dy| {
                if let Some(carousel) = carousel_weak.upgrade() {
                    carousel.handle_scroll(dx, dy);
                }
                glib::Propagation::Stop
            });
        }
        carousel.add_controller(scroll);

        // Animation loop -- runs continuously as long as the window is
        // open (a transient window, negligible cost). Weak reference so as
        // not to create a strong cycle with the callback the widget holds
        // on itself.
        {
            let carousel_weak = carousel.downgrade();
            carousel.add_tick_callback(move |_, clock| {
                if let Some(carousel) = carousel_weak.upgrade() {
                    carousel.imp().tick(clock);
                }
                glib::ControlFlow::Continue
            });
        }

        carousel
    }

    fn handle_card_click(&self, index: usize) {
        let len = self.imp().entries.borrow().len();
        if len == 0 {
            return;
        }
        if index == self.focused_index() {
            self.activate_focused();
            return;
        }
        let len_f = len as f64;
        let focused = self.focused_index() as f64;
        let mut diff = index as f64 - focused;
        if diff > len_f / 2.0 {
            diff -= len_f;
        } else if diff < -len_f / 2.0 {
            diff += len_f;
        }
        self.set_target(self.imp().target.get() + diff);
    }

    fn handle_scroll(&self, dx: f64, dy: f64) {
        let delta = if dx.abs() > dy.abs() { dx } else { dy };
        if delta.abs() < 0.001 {
            return;
        }
        let accum = self.imp().scroll_accum.get() + delta;
        let steps = accum.trunc();
        if steps != 0.0 {
            self.set_target(self.imp().target.get() + steps);
            self.imp().scroll_accum.set(accum - steps);
        } else {
            self.imp().scroll_accum.set(accum);
        }
    }

    /// Writes `target` AND notifies `target_changed_cb` with the resulting
    /// focus index -- single choke point for every INTERACTIVE navigation
    /// (see the field's doc), so windowed thumbnail loading can never miss
    /// a focus change.
    fn set_target(&self, value: f64) {
        self.imp().target.set(value);
        if let Some(cb) = self.imp().target_changed_cb.borrow().as_ref() {
            cb(self.focused_index());
        }
    }

    /// Index of the currently focused card, derived from `target` (not
    /// `offset`, which is only its animated/interpolated version).
    pub fn focused_index(&self) -> usize {
        let len = self.imp().entries.borrow().len();
        if len == 0 {
            return 0;
        }
        self.imp().target.get().round().rem_euclid(len as f64) as usize
    }

    pub fn len(&self) -> usize {
        self.imp().entries.borrow().len()
    }

    pub fn card_at(&self, index: usize) -> Option<Card> {
        self.imp().entries.borrow().get(index).cloned()
    }

    /// Moves the focus target by `delta` cards (keyboard navigation, see
    /// main.rs); the animation toward this new target is handled by
    /// `tick`.
    pub fn move_focus(&self, delta: i32) {
        self.set_target(self.imp().target.get() + delta as f64);
    }

    /// Positions focus directly on `index`, without scrolling from 0 --
    /// used once at launch to start on the last wallpaper applied in
    /// Static mode (see `apply::last_static`) rather than the first card
    /// in the list. Also sets the cascade entrance's starting point (see
    /// `reveal_origin`) to this same index, so the entrance animation
    /// spills out from this card rather than from the start of the list.
    pub fn set_focus_index(&self, index: usize) {
        let len = self.imp().entries.borrow().len();
        if len == 0 || index >= len {
            return;
        }
        self.imp().target.set(index as f64);
        self.imp().offset.set(index as f64);
        self.imp().reveal_origin.set(index as f64);
    }

    pub fn activate_focused(&self) {
        let idx = self.focused_index();
        if let Some(cb) = self.imp().activate_cb.borrow().as_ref() {
            cb(idx);
        }
    }

    /// Called when the focused card is activated (Enter, or click on a
    /// card that already has focus).
    pub fn connect_activate(&self, f: impl Fn(usize) + 'static) {
        *self.imp().activate_cb.borrow_mut() = Some(Box::new(f));
    }

    /// Called on every interactive focus change (see `set_target`) --
    /// used by main.rs to recompute the window of thumbnails to
    /// load/unload.
    pub fn connect_target_changed(&self, f: impl Fn(usize) + 'static) {
        *self.imp().target_changed_cb.borrow_mut() = Some(Box::new(f));
    }
}
