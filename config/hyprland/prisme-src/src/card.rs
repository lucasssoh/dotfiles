//! Carousel "card" widget: a wallpaper thumbnail drawn as a parallelogram
//! ("italic" effect), whose focus, reveal, and selection are driven by
//! carousel.rs. Rendered entirely in GSK (snapshot) rather than Cairo to
//! stay smooth on a layer-shell surface — see the note on `measure` below
//! for the file's most important sizing constraint.

use gtk4::glib;
use gtk4::prelude::*;
use gtk4::subclass::prelude::*;
use gtk4::{gdk, graphene, gsk, pango};
use std::cell::{Cell, OnceCell, RefCell};
use std::path::Path;

use crate::wallpapers::Wallpaper;

/// Raw filename -> readable label for the card's caption: extension
/// stripped, dashes and underscores treated as spaces, all uppercase. E.g.
/// "oleksandr-kozachenko-hands-study-5.jpg" ->
/// "OLEKSANDR KOZACHENKO HANDS STUDY 5".
fn display_name(filename: &str) -> String {
    let stem = Path::new(filename)
        .file_stem()
        .and_then(|s| s.to_str())
        .unwrap_or(filename);
    stem.replace(['-', '_'], " ").to_uppercase()
}

/// Slope of the "italic" angle as a fraction of the card's height (not a
/// fixed pixel count) -- height varies with focus and selection (see
/// carousel.rs), so a constant px offset would give a VISUALLY different
/// angle depending on card size (a short card looks more slanted than a
/// tall one for the same px offset). Deriving it from height keeps every
/// card at exactly the same slope, whatever its current size.
pub const SKEW_RATIO: f64 = 0.1;

pub const WIDTH_UNFOCUSED: f64 = 180.0;
pub const WIDTH_FOCUSED: f64 = 520.0;
pub const HEIGHT_UNFOCUSED: f64 = 320.0;
pub const HEIGHT_FOCUSED: f64 = 460.0;

/// Corner radius for the card's own rounded parallelogram (and the
/// caption band cut to match it) -- "tout arrondir", no pointed corners
/// anywhere, asked for. See `round_corner` for how a sharp vertex becomes
/// this.
const CARD_CORNER_RADIUS: f64 = 16.0;
/// Points sampled per rounded corner -- see `round_corner`.
const CORNER_STEPS: usize = 8;

/// Replaces a sharp polygon corner with a small rounded fillet, using a
/// quadratic Bézier (the original vertex as control point) between two
/// points backed off along the adjacent edges -- not a true circular arc:
/// much simpler to get right than computing a tangent-fillet center, and
/// at this radius the visual difference is imperceptible. `radius` is
/// clamped to at most half of either adjacent edge's length, so short
/// edges never produce overlapping/self-intersecting fillets (and
/// `radius <= 0` degenerates to just the original sharp corner, i.e. the
/// pre-rounding behavior).
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

/// Horizontal offset (px) of the slope for a card of size (w,h) --
/// centralized here, reused by `carousel.rs` to compute spacing between
/// cards (see its doc), so the two stay in agreement.
pub fn skew_for(w: f64, h: f64) -> f64 {
    (h * SKEW_RATIO).min(w * 0.3)
}

mod imp {
    use super::*;

    #[derive(Default)]
    pub struct Card {
        pub texture: RefCell<Option<gdk::Texture>>,
        /// Dimensions of the source file (not the downscaled texture), for
        /// the caption -- e.g. "3840×2160" even though the displayed
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
            let w = widget.width() as f64;
            let h = widget.height() as f64;
            let reveal = self.reveal.get();
            if w <= 0.0 || h <= 0.0 || reveal <= 0.001 {
                return;
            }

            let skew = skew_for(w, h);
            let path = parallelogram_path(w, h, skew);

            // Fill clipped to the parallelogram -- GPU equivalent of the
            // old implementation's Cairo clip + paint.
            snapshot.push_fill(&path, gsk::FillRule::Winding);
            match &*self.texture.borrow() {
                Some(tex) => {
                    let tw = tex.width() as f64;
                    let th = tex.height() as f64;
                    // "cover": the larger of the two ratios fills the
                    // whole box, cropping if needed.
                    let scale = (w / tw).max(h / th).max(0.0001);
                    let dw = tw * scale;
                    let dh = th * scale;
                    let dx = (w - dw) / 2.0;
                    let dy = (h - dh) / 2.0;
                    let bounds =
                        graphene::Rect::new(dx as f32, dy as f32, dw as f32, dh as f32);
                    snapshot.append_scaled_texture(tex, gsk::ScalingFilter::Trilinear, &bounds);

                    // Non-focused cards are dimmed.
                    let dim = (1.0 - self.focus.get()) * 0.55;
                    if dim > 0.001 {
                        let full = graphene::Rect::new(0.0, 0.0, w as f32, h as f32);
                        snapshot.append_color(&gdk::RGBA::new(0.0, 0.0, 0.0, dim as f32), &full);
                    }
                }
                None => {
                    // Thumbnail not loaded yet -- neutral flat fill.
                    let full = graphene::Rect::new(0.0, 0.0, w as f32, h as f32);
                    snapshot
                        .append_color(&gdk::RGBA::new(0.11, 0.11, 0.12, 1.0), &full);
                }
            }
            snapshot.pop();

            // No outline -- focus and selection already read clearly from
            // size/brightness (focus) and height (selection, see
            // carousel.rs), an extra border added nothing.
            let focus = self.focus.get();

            // Name + dimensions -- fades in progressively with focus
            // instead of the old DrawingArea version's binary threshold.
            if focus > 0.15 {
                let alpha = (((focus - 0.15) / 0.45) as f32).clamp(0.0, 1.0);
                if let Some(wallpaper) = self.wallpaper.get() {
                    // Padding and font sizes deliberately compact (a
                    // discreet caption, not an info banner) -- measured via
                    // pixel_size() rather than guessed offsets, so the band
                    // hugs the actual content exactly regardless of the
                    // system font.
                    const PAD_X: f64 = 10.0;
                    const PAD_TOP: f64 = 5.0;
                    const PAD_BOTTOM: f64 = 5.0;
                    const LINE_GAP: f64 = 1.0;
                    const NAME_FONT_PX: f64 = 13.0;
                    const DIMS_FONT_PX: f64 = 11.0;

                    // Anchored right rather than left: the parallelogram's
                    // bottom-right corner is more open (obtuse angle) than
                    // the bottom-left (acute angle, see skewed_slice_path)
                    // -- text has more room to breathe on the wide side.
                    //
                    // Width subtracts `skew` on top of the padding: the
                    // card's right edge is only vertical at x=w at the very
                    // top (y=0); it recedes to x=w-skew at the bottom (y=h,
                    // see skewed_slice_path). A straight (non-slanted) text
                    // box aligned right must therefore target that furthest
                    // point -- otherwise the text overflows past the card's
                    // slanted side near the bottom of the band, where the
                    // gap between "w" and the real edge is largest.
                    let mut name_font = pango::FontDescription::new();
                    name_font.set_absolute_size(NAME_FONT_PX * pango::SCALE as f64);
                    let name_layout = widget.create_pango_layout(Some(&display_name(&wallpaper.name)));
                    name_layout.set_font_description(Some(&name_font));
                    name_layout.set_ellipsize(pango::EllipsizeMode::Middle);
                    name_layout.set_alignment(pango::Alignment::Right);
                    name_layout.set_width(((w - skew - PAD_X * 2.0).max(0.0) * pango::SCALE as f64) as i32);
                    let name_h = name_layout.pixel_size().1 as f64;

                    let (dw, dh) = self.orig_dims.get();
                    let dims_layout = (dw > 0 && dh > 0).then(|| {
                        let mut dims_font = pango::FontDescription::new();
                        dims_font.set_absolute_size(DIMS_FONT_PX * pango::SCALE as f64);
                        let layout = widget.create_pango_layout(Some(&format!("{dw}\u{00d7}{dh}")));
                        layout.set_font_description(Some(&dims_font));
                        layout.set_alignment(pango::Alignment::Right);
                        layout.set_width(((w - skew - PAD_X * 2.0).max(0.0) * pango::SCALE as f64) as i32);
                        layout
                    });
                    let dims_h = dims_layout.as_ref().map_or(0.0, |l| l.pixel_size().1 as f64);

                    // Black band behind the text, sized exactly to the
                    // content measured above. Cut as a slice of the SAME
                    // parallelogram as the card (see skewed_slice_path)
                    // rather than a straight rectangle -- so its sides
                    // follow the card's edge slope instead of cutting
                    // through it at a right angle. Slight bleed (1px)
                    // beyond the real edge on each side: without it, GPU
                    // anti-aliasing on this edge and the image clip's
                    // -- slightly different -- edge left a thin uncovered
                    // sliver.
                    let content_h = name_h + if dims_layout.is_some() { LINE_GAP + dims_h } else { 0.0 };
                    let band_top = (h - (PAD_TOP + content_h + PAD_BOTTOM)).max(0.0);
                    let band_path = skewed_slice_path(w, h, skew, band_top, h, 1.0, CARD_CORNER_RADIUS);
                    snapshot.push_fill(&band_path, gsk::FillRule::Winding);
                    let full = graphene::Rect::new(0.0, 0.0, w as f32, h as f32);
                    snapshot.append_color(&gdk::RGBA::new(0.0, 0.0, 0.0, 0.8 * alpha), &full);
                    snapshot.pop();

                    let text_color = gdk::RGBA::new(0.949, 0.949, 0.969, alpha);
                    let name_y = band_top + PAD_TOP;
                    snapshot.save();
                    snapshot.translate(&graphene::Point::new(PAD_X as f32, name_y as f32));
                    snapshot.append_layout(&name_layout, &text_color);
                    snapshot.restore();

                    if let Some(dims_layout) = dims_layout {
                        let dims_color = gdk::RGBA::new(0.557, 0.557, 0.576, alpha);
                        let dims_y = name_y + name_h + LINE_GAP;
                        snapshot.save();
                        snapshot.translate(&graphene::Point::new(PAD_X as f32, dims_y as f32));
                        snapshot.append_layout(&dims_layout, &dims_color);
                        snapshot.restore();
                    }
                }
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
    /// background.
    pub fn set_texture(&self, texture: gdk::Texture, orig_width: i32, orig_height: i32) {
        self.imp().orig_dims.set((orig_width, orig_height));
        *self.imp().texture.borrow_mut() = Some(texture);
        self.queue_draw();
    }

    /// Frees the texture of a card that fell out of the loading window
    /// (see main.rs) -- falls back to the neutral "not loaded yet" flat
    /// fill (see `snapshot()`), reloaded on demand if focus comes back to
    /// it. `orig_dims` reset to zero too: without that, the info band
    /// would still show the unloaded image's dimensions under a flat fill
    /// that no longer shows anything.
    pub fn clear_texture(&self) {
        *self.imp().texture.borrow_mut() = None;
        self.imp().orig_dims.set((0, 0));
        self.queue_draw();
    }

    /// t ∈ [0,1] -- 0 = resting card, 1 = focused card. Drives brightness
    /// and label appearance; size is derived from the same value by the
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

    /// Marks the card as included in the multi-selection (Dynamic mode).
    /// Only affects internal state: it's carousel.rs that translates
    /// selection into a height/appearance change.
    pub fn set_selected(&self, selected: bool) {
        self.imp().selected.set(selected);
        self.queue_draw();
    }

    pub fn is_selected(&self) -> bool {
        self.imp().selected.get()
    }
}

/// Builds the outline of the card's "italic" parallelogram, slanted by
/// `skew` pixels to the right at the top -- corners rounded by
/// CARD_CORNER_RADIUS, no pointed corners.
fn parallelogram_path(w: f64, h: f64, skew: f64) -> gsk::Path {
    skewed_slice_path(w, h, skew, 0.0, h, 0.0, CARD_CORNER_RADIUS)
}

/// Outline of a horizontal slice of the same parallelogram, between
/// `y_top` and `y_bottom` (0.0 and h with bleed=0.0 give
/// parallelogram_path above). Used to cut the caption band with exactly
/// the same slope as the card's sides, rather than a straight rectangle
/// that would slice through it at a right angle. `bleed` widens the
/// outline by `bleed` px on each side (left/right only) -- useful for the
/// band, whose edges need to bleed slightly past the card's real edge so
/// as not to leave a sliver uncovered by GPU anti-aliasing on the two
/// slanted edges. `radius` rounds all 4 corners (see `round_corner`) --
/// the band uses the SAME radius as the card outline itself when it cuts
/// through the card's own bottom corners, otherwise a sharp band corner
/// would visibly poke out past the now-rounded card silhouette behind it.
/// `h` non-zero is guaranteed by the caller (snapshot() returns early if
/// h <= 0.0).
fn skewed_slice_path(
    w: f64,
    h: f64,
    skew: f64,
    y_top: f64,
    y_bottom: f64,
    bleed: f64,
    radius: f64,
) -> gsk::Path {
    let x_left = |y: f64| skew * (1.0 - y / h) - bleed;
    let x_right = |y: f64| w - skew * (y / h) + bleed;
    let tl = (x_left(y_top), y_top);
    let tr = (x_right(y_top), y_top);
    let br = (x_right(y_bottom), y_bottom);
    let bl = (x_left(y_bottom), y_bottom);

    let builder = gsk::PathBuilder::new();
    let mut started = false;
    for (prev, corner, next) in [(bl, tl, tr), (tl, tr, br), (tr, br, bl), (br, bl, tl)] {
        for (x, y) in round_corner(prev, corner, next, radius, CORNER_STEPS) {
            if started {
                builder.line_to(x as f32, y as f32);
            } else {
                builder.move_to(x as f32, y as f32);
                started = true;
            }
        }
    }
    builder.close();
    builder.to_path()
}
