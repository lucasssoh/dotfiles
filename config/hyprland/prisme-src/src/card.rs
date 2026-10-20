//! Carousel "card" widget: a wallpaper thumbnail drawn as a straight
//! rounded rectangle, whose focus, reveal, and selection are driven by
//! carousel.rs. Rendered entirely in GSK (snapshot) rather than Cairo to
//! stay smooth on a layer-shell surface — see the note on `measure` below
//! for the file's most important sizing constraint.
//!
//! The name and dimensions are no longer drawn here: the focused wallpaper
//! is previewed full screen (backdrop.rs) and captioned by main.rs. A
//! light/dark pair opens with focus: the half in the preview takes three
//! quarters of the card, the other stays along the edge, past a slanted cut.

use gtk4::glib;
use gtk4::prelude::*;
use gtk4::subclass::prelude::*;
use gtk4::{gdk, graphene, gsk};
use std::cell::{Cell, OnceCell, RefCell};

use crate::wallpapers::Wallpaper;

/// A resting card is a portrait slice; the focused one widens to the
/// screen's 16:10, at the same height.
pub const WIDTH_UNFOCUSED: f64 = 100.0;
pub const WIDTH_FOCUSED: f64 = 288.0;
pub const HEIGHT_UNFOCUSED: f64 = 180.0;
pub const HEIGHT_FOCUSED: f64 = 180.0;

const CARD_CORNER_RADIUS: f32 = 16.0;

/// How dark a resting card gets: the full-screen preview carries the
/// focus, so the cards around it only need to step back a little.
const REST_DIM: f64 = 0.3;

/// Share of the focused card the previewed half of a pair takes.
const SHOWN_SHARE: f32 = 0.76;
/// Horizontal run of the slanted cut, as a share of the card's width.
const CUT_SLANT: f32 = 0.06;
/// How dark the half not in the preview gets, on the focused card.
const OTHER_DIM: f32 = 0.5;
/// Length of the cut's slide when C swaps the halves.
const SWAP_MS: f64 = 200.0;

const INK: gdk::RGBA = gdk::RGBA::new(0.949, 0.949, 0.969, 1.0);

mod imp {
    use super::*;

    #[derive(Default)]
    pub struct Card {
        pub texture: RefCell<Option<gdk::Texture>>,
        /// The dark half of a light/dark pair (see wallpapers.rs), loaded
        /// alongside `texture`; stays None for a wallpaper without one.
        pub dark_texture: RefCell<Option<gdk::Texture>>,
        /// The desktop's colour scheme: which half of a pair is shown.
        pub dark_scheme: Cell<bool>,
        /// Which half the preview shows, eased: 0 light, 1 dark. Only
        /// read while the card has focus.
        pub shown: Cell<f64>,
        pub shown_target: Cell<f64>,
        pub swap_start: Cell<Option<(i64, f64)>>,
        pub ticking: Cell<bool>,
        /// Dimensions of the source file (not the downscaled texture), for
        /// main.rs's caption -- e.g. "3840 × 2160" even though the
        /// thumbnail is smaller.
        pub orig_dims: Cell<(i32, i32)>,
        pub focus: Cell<f64>,
        pub reveal: Cell<f64>,
        pub selected: Cell<bool>,
        pub wallpaper: OnceCell<Wallpaper>,
    }

    #[glib::object_subclass]
    impl ObjectSubclass for Card {
        const NAME: &'static str = "PrismeCard";
        type Type = super::Card;
        type ParentType = gtk4::Widget;
    }

    impl ObjectImpl for Card {}

    impl WidgetImpl for Card {
        // Size is entirely driven by the carousel (via `size_allocate` on
        // this widget) -- no size preference of its own, otherwise every
        // focus change would trigger a `queue_resize` bubbling up to the
        // window 180 times a second (that's exactly what was inflating the
        // layer-shell surface before this rewrite).
        fn measure(&self, _orientation: gtk4::Orientation, _for_size: i32) -> (i32, i32, i32, i32) {
            (0, 0, -1, -1)
        }

        fn snapshot(&self, snapshot: &gtk4::Snapshot) {
            let widget = self.obj();
            let w = widget.width() as f32;
            let h = widget.height() as f32;
            if w <= 0.0 || h <= 0.0 || self.reveal.get() <= 0.001 {
                return;
            }
            let focus = self.focus.get();
            let full = graphene::Rect::new(0.0, 0.0, w, h);

            snapshot.push_rounded_clip(&rounded(&full, 0.0, CARD_CORNER_RADIUS));
            let imp_pair = (self.texture.borrow().clone(), self.dark_texture.borrow().clone());
            match (imp_pair, widget.shown_texture()) {
                ((Some(light), Some(dark)), _) => {
                    // Where the dark half starts, from the left: past the
                    // card at rest (the scheme's half fills it), at a
                    // quarter or three quarters with focus.
                    let rest = if self.dark_scheme.get() { -CUT_SLANT } else { 1.0 + CUT_SLANT };
                    let shown = self.shown.get() as f32;
                    let open = (1.0 - SHOWN_SHARE) + (2.0 * SHOWN_SHARE - 1.0) * (1.0 - shown);
                    let cut = rest + (open - rest) * focus as f32;
                    draw_cover(snapshot, &light, w as f64, h as f64);
                    let f = focus as f32;
                    if f * shown > 0.001 {
                        snapshot.append_color(&gdk::RGBA::new(0.0, 0.0, 0.0, OTHER_DIM * f * shown), &full);
                    }
                    let path = gsk::PathBuilder::new();
                    path.move_to((cut + CUT_SLANT) * w, 0.0);
                    path.line_to(w + 1.0, 0.0);
                    path.line_to(w + 1.0, h);
                    path.line_to((cut - CUT_SLANT) * w, h);
                    path.close();
                    snapshot.push_fill(&path.to_path(), gsk::FillRule::Winding);
                    draw_cover(snapshot, &dark, w as f64, h as f64);
                    if f * (1.0 - shown) > 0.001 {
                        snapshot.append_color(&gdk::RGBA::new(0.0, 0.0, 0.0, OTHER_DIM * f * (1.0 - shown)), &full);
                    }
                    snapshot.pop();
                    let dim = (1.0 - focus) * REST_DIM;
                    if dim > 0.001 {
                        snapshot.append_color(&gdk::RGBA::new(0.0, 0.0, 0.0, dim as f32), &full);
                    }
                }
                (_, Some(tex)) => {
                    draw_cover(snapshot, &tex, w as f64, h as f64);
                    let dim = (1.0 - focus) * REST_DIM;
                    if dim > 0.001 {
                        snapshot.append_color(&gdk::RGBA::new(0.0, 0.0, 0.0, dim as f32), &full);
                    }
                }
                // Thumbnail not loaded yet -- neutral flat fill.
                (_, None) => snapshot.append_color(&gdk::RGBA::new(0.11, 0.11, 0.12, 1.0), &full),
            }
            snapshot.pop();

            // Focus frame: a white ring set off the picture by a thin dark
            // gap, so it reads on a white wallpaper too. Drawn outside the
            // card (overflow is visible, see `Card::new`).
            let ring = focus.clamp(0.0, 1.0) as f32;
            if ring > 0.01 {
                let gap = rounded(&full, 1.5, CARD_CORNER_RADIUS);
                snapshot.append_border(&gap, &[1.5; 4], &[gdk::RGBA::new(0.0, 0.0, 0.0, 0.55 * ring); 4]);
                let outer = rounded(&full, 4.0, CARD_CORNER_RADIUS);
                snapshot.append_border(&outer, &[2.5; 4], &[gdk::RGBA::new(INK.red(), INK.green(), INK.blue(), ring); 4]);
            }

            // Picked for the slideshow: a small white disc with a check.
            if self.selected.get() {
                const D: f32 = 18.0;
                const INSET: f32 = 8.0;
                let (x, y) = (w - INSET - D, INSET);
                let disc = graphene::Rect::new(x, y, D, D);
                snapshot.push_rounded_clip(&rounded(&disc, 0.0, D / 2.0));
                snapshot.append_color(&INK, &disc);
                snapshot.pop();
                let check = gsk::PathBuilder::new();
                check.move_to(x + 5.0, y + 9.5);
                check.line_to(x + 8.0, y + 12.5);
                check.line_to(x + 13.5, y + 6.5);
                let stroke = gsk::Stroke::new(2.0);
                stroke.set_line_cap(gsk::LineCap::Round);
                stroke.set_line_join(gsk::LineJoin::Round);
                snapshot.append_stroke(&check.to_path(), &stroke, &gdk::RGBA::new(0.047, 0.047, 0.055, 1.0));
            }
        }
    }
}

glib::wrapper! {
    /// Public widget exposed to the rest of the program; all the logic
    /// lives in `imp::Card` (standard gtk4-rs GObject subclass pattern).
    pub struct Card(ObjectSubclass<imp::Card>) @extends gtk4::Widget;
}

impl Card {
    /// Builds a card for this wallpaper. The thumbnail isn't loaded yet:
    /// `set_texture` is called later, once decoding finishes on the
    /// thumbs.rs side.
    pub fn new(wallpaper: Wallpaper) -> Self {
        let card: Self = glib::Object::builder().build();
        let _ = card.imp().wallpaper.set(wallpaper);
        card.set_overflow(gtk4::Overflow::Visible);
        card
    }

    pub fn wallpaper(&self) -> &Wallpaper {
        self.imp().wallpaper.get().expect("wallpaper not initialized")
    }

    /// Received from thumbs.rs once the thumbnail has decoded in the
    /// background -- `dark` for the dark half of a pair. The caption's
    /// dimensions are the light file's when it has one.
    pub fn set_texture(&self, dark: bool, texture: gdk::Texture, orig_width: i32, orig_height: i32) {
        let imp = self.imp();
        if !dark || imp.texture.borrow().is_none() {
            imp.orig_dims.set((orig_width, orig_height));
        }
        let slot = if dark { &imp.dark_texture } else { &imp.texture };
        *slot.borrow_mut() = Some(texture);
        self.queue_draw();
    }

    /// The thumbnail of one half (`dark`), falling back to the other half
    /// while that one is still loading -- main.rs stretches it over the
    /// screen until the sharp preview arrives.
    pub fn texture(&self, dark: bool) -> Option<gdk::Texture> {
        let imp = self.imp();
        let (wanted, other) = if dark { (&imp.dark_texture, &imp.texture) } else { (&imp.texture, &imp.dark_texture) };
        wanted.borrow().clone().or_else(|| other.borrow().clone())
    }

    /// The half the colour scheme asks for, or whichever has loaded.
    fn shown_texture(&self) -> Option<gdk::Texture> {
        self.texture(self.imp().dark_scheme.get())
    }

    /// Dimensions of the source file, (0, 0) until the thumbnail loads.
    pub fn orig_dims(&self) -> (i32, i32) {
        self.imp().orig_dims.get()
    }

    /// The desktop's colour scheme changed (or is read at launch): pairs
    /// show their other half.
    pub fn set_dark_scheme(&self, dark: bool) {
        if self.imp().dark_scheme.replace(dark) != dark {
            self.set_shown_dark(dark, false);
            self.queue_draw();
        }
    }

    /// Which half of a pair the preview shows (main.rs, on focus and on
    /// C): with `animate`, the cut slides across instead of jumping.
    pub fn set_shown_dark(&self, dark: bool, animate: bool) {
        let imp = self.imp();
        let target = if dark { 1.0 } else { 0.0 };
        imp.shown_target.set(target);
        if !animate {
            imp.shown.set(target);
            imp.swap_start.set(None);
            self.queue_draw();
            return;
        }
        imp.swap_start.set(None);
        if imp.ticking.replace(true) {
            return;
        }
        self.add_tick_callback(|card, clock| {
            let imp = card.imp();
            let now = clock.frame_time();
            let (start, from) = *imp.swap_start.get().get_or_insert((now, imp.shown.get()));
            imp.swap_start.set(Some((start, from)));
            let t = ((now - start) as f64 / 1000.0 / SWAP_MS).clamp(0.0, 1.0);
            let eased = t * t * (3.0 - 2.0 * t);
            let target = imp.shown_target.get();
            imp.shown.set(from + (target - from) * eased);
            card.queue_draw();
            if t >= 1.0 || imp.swap_start.get().is_none() {
                imp.shown.set(target);
                imp.swap_start.set(None);
                imp.ticking.set(false);
                glib::ControlFlow::Break
            } else {
                glib::ControlFlow::Continue
            }
        });
    }

    /// Frees the texture of a card that fell out of the loading window
    /// (see main.rs) -- falls back to the neutral "not loaded yet" flat
    /// fill (see `snapshot()`), reloaded on demand if focus comes back to
    /// it. `orig_dims` reset to zero too, so the caption never shows the
    /// dimensions of a picture that is no longer loaded.
    pub fn clear_texture(&self) {
        *self.imp().texture.borrow_mut() = None;
        *self.imp().dark_texture.borrow_mut() = None;
        self.imp().orig_dims.set((0, 0));
        self.queue_draw();
    }

    /// t ∈ [0,1] -- 0 = resting card, 1 = focused card. Drives brightness
    /// and the focus ring; size is derived from the same value by the
    /// carousel (see `carousel.rs`), not stored here.
    pub fn set_focus(&self, t: f64) {
        self.imp().focus.set(t.clamp(0.0, 1.0));
        self.queue_draw();
    }

    /// Current focus value, see `set_focus`.
    pub fn focus(&self) -> f64 {
        self.imp().focus.get()
    }

    /// t ∈ [0,1] -- cascade entrance animation at launch.
    pub fn set_reveal(&self, t: f64) {
        let t = t.clamp(0.0, 1.0);
        self.imp().reveal.set(t);
        self.set_opacity(t);
        self.queue_draw();
    }

    /// Marks the card as included in the multi-selection (Dynamic mode):
    /// drawn as a check here, and as extra height by carousel.rs.
    pub fn set_selected(&self, selected: bool) {
        self.imp().selected.set(selected);
        self.queue_draw();
    }

    pub fn is_selected(&self) -> bool {
        self.imp().selected.get()
    }
}

/// `rect` grown by `outset` on every side, its corners rounded to match:
/// the radius grows with it, so a ring stays concentric with the card.
fn rounded(rect: &graphene::Rect, outset: f32, radius: f32) -> gsk::RoundedRect {
    let grown = graphene::Rect::new(
        rect.x() - outset,
        rect.y() - outset,
        rect.width() + 2.0 * outset,
        rect.height() + 2.0 * outset,
    );
    gsk::RoundedRect::from_rect(grown, radius + outset)
}

/// Draws `tex` to fill a w×h box ("cover": the larger of the two ratios
/// fills the whole box, cropping if needed), clipped by whatever the
/// caller has pushed.
fn draw_cover(snapshot: &gtk4::Snapshot, tex: &gdk::Texture, w: f64, h: f64) {
    let tw = tex.width() as f64;
    let th = tex.height() as f64;
    let scale = (w / tw).max(h / th).max(0.0001);
    let dw = tw * scale;
    let dh = th * scale;
    let dx = (w - dw) / 2.0;
    let dy = (h - dh) / 2.0;
    let bounds = graphene::Rect::new(dx as f32, dy as f32, dw as f32, dh as f32);
    snapshot.append_scaled_texture(tex, gsk::ScalingFilter::Trilinear, &bounds);
}
