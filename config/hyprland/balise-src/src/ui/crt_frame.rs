//! `CrtFrame`: single-child container that clips its content to a
//! CRT-style curved silhouette instead of a plain rounded rect.
//!
//! Why this exists at all: GTK CSS's `border-radius` only does
//! elliptical CORNERS -- there is no `clip-path` in GTK CSS, so a
//! straight edge bulging outward in the middle (the "petit bend" asked
//! for, matching the same treatment given to Quickshell's bar pills)
//! can't be expressed in balise/style.css no matter how it's written.
//! This widget builds the outline itself with `gsk::PathBuilder`
//! instead of leaning on CSS -- the Rust/GTK4 sibling of
//! quickshell/bar/modules/crtPath.js, same math (quadratic Bézier edges,
//! cubic-approximated circular corners), reimplemented here because GSK
//! paths and QtQuick.Shapes paths aren't interchangeable. Keep the two
//! in sync by eye if the curve formula ever changes.
//!
//! Two nested curves are painted, not one -- the same outer-fill /
//! inner-clip split GlassRim.qml uses for its ring: the OUTER path is
//! filled with the panel's own border gradient (copied straight from
//! balise/style.css's `.balise-panel`, 135deg to match), then a clip is
//! pushed using the INNER path (offset inward by the CSS margin that
//! used to be `.balise-panel-inner`'s own job) before the single child
//! -- still a plain CSS-styled Box, background and all -- is painted.
//! Whatever that child draws, including its own rectangular CSS
//! background, gets cut to the inner curve for free by the pushed clip;
//! nothing about the child's own styling needs to change.

use gtk4::gdk;
use gtk4::glib;
use gtk4::graphene;
use gtk4::gsk;
use gtk4::prelude::*;
use gtk4::subclass::prelude::*;

// Same "circle via 4 cubics" constant crtPath.js uses.
const K: f32 = 0.552_284_75;

// Copied from balise/style.css's `.balise-panel` background gradient
// (135deg, 5 stops) -- kept here rather than re-parsed from CSS since
// GSK gradients need graphene::Point/gsk::ColorStop values, not a CSS
// string, and this ring is the one visual GTK CSS genuinely can't draw
// once its edges bulge (see the module comment above).
const BORDER_STOPS: [(f32, f32, f32, f32, f32); 5] = [
    // (offset, r, g, b, a) -- r/g/b already 0..1, matching the CSS rgba()'s own 0..255 values / 255.
    (0.00, 234.0 / 255.0, 234.0 / 255.0, 238.0 / 255.0, 0.90),
    (0.25, 170.0 / 255.0, 172.0 / 255.0, 180.0 / 255.0, 0.65),
    (0.50, 130.0 / 255.0, 132.0 / 255.0, 140.0 / 255.0, 0.45),
    (0.75, 90.0 / 255.0, 92.0 / 255.0, 98.0 / 255.0, 0.30),
    (1.00, 60.0 / 255.0, 62.0 / 255.0, 68.0 / 255.0, 0.18),
];

// A short straight edge can't absorb a big bulge -- see crtPath.js's
// matching comment (its sibling implementation) for why edgeLen/4, with
// a hard cutoff below 8px, is what actually stayed clean under
// CurveRenderer/GSK tessellation live.
fn safe_bulge(edge_len: f32, bulge: f32) -> f32 {
    if edge_len < 8.0 { 0.0 } else { bulge.min(edge_len * 0.25) }
}

// The quadratic-Bézier bulge edges below approximate a circular arc:
// chord 2×a, sagitta (max height off the chord) = bulge. The inner ring
// used to get its own bulge by just reusing the outer one minus
// `margin` -- but a circle's sagitta does NOT shrink linearly with its
// radius, so that undershot near the edge's flat ends and overshot at
// the curve's own peak: the ring visibly THICKENED right at the bulge,
// a crescent/half-moon instead of a constant-width arc (confirmed live,
// same bug crtPath.js's own comment documents). This solves for the
// sagitta of the SAME circle instead -- same chord, radius reduced by
// exactly `t` -- a true offset, the same exact move `inner_radius`
// already does for the (circular) corners.
fn inset_sagitta(a: f32, bulge: f32, t: f32) -> f32 {
    if bulge <= 0.0 || a <= 0.0 {
        return 0.0;
    }
    let r = (a * a + bulge * bulge) / (2.0 * bulge);
    let r_in = r - t;
    if r_in <= a {
        return 0.0;
    }
    r_in - (r_in * r_in - a * a).sqrt()
}

/// Emits the actual path for ALREADY-DECIDED per-edge bulge values --
/// `crt_path()` below is the normal entry point (derives those 4 from
/// one scalar via `safe_bulge()`); this one exists so the inner ring can
/// supply its own, separately-inset values instead (see
/// `inset_sagitta()` above). Mirrors crtPath.js's `buildEdges()` step
/// for step.
#[allow(clippy::too_many_arguments)]
fn build_edges(
    w: f32, h: f32, r_tl: f32, r_tr: f32, r_br: f32, r_bl: f32,
    b_top: f32, b_right: f32, b_bottom: f32, b_left: f32, ox: f32, oy: f32,
) -> gsk::Path {
    // Same clamp Qt's Rectangle/GTK CSS border-radius both apply
    // automatically -- see crtPath.js's matching comment (its sibling):
    // a corner radius bigger than half the box self-crosses instead of
    // just rounding.
    let max_r = (w.min(h) / 2.0).max(0.0);
    let r_tl = r_tl.min(max_r);
    let r_tr = r_tr.min(max_r);
    let r_br = r_br.min(max_r);
    let r_bl = r_bl.min(max_r);
    let b_top = if r_tl > 0.0 && r_tr > 0.0 { b_top } else { 0.0 };
    let b_right = if r_tr > 0.0 && r_br > 0.0 { b_right } else { 0.0 };
    let b_bottom = if r_br > 0.0 && r_bl > 0.0 { b_bottom } else { 0.0 };
    let b_left = if r_bl > 0.0 && r_tl > 0.0 { b_left } else { 0.0 };

    let k_tl = K * r_tl;
    let k_tr = K * r_tr;
    let k_br = K * r_br;
    let k_bl = K * r_bl;

    let pb = gsk::PathBuilder::new();
    pb.move_to(r_tl + ox, oy);
    pb.quad_to(w / 2.0 + ox, oy - 2.0 * b_top, w - r_tr + ox, oy);
    pb.cubic_to(w - r_tr + k_tr + ox, oy, w + ox, r_tr - k_tr + oy, w + ox, r_tr + oy);
    pb.quad_to(w + 2.0 * b_right + ox, h / 2.0 + oy, w + ox, h - r_br + oy);
    pb.cubic_to(w + ox, h - r_br + k_br + oy, w - r_br + k_br + ox, h + oy, w - r_br + ox, h + oy);
    pb.quad_to(w / 2.0 + ox, h + 2.0 * b_bottom + oy, r_bl + ox, h + oy);
    pb.cubic_to(r_bl - k_bl + ox, h + oy, ox, h - r_bl + k_bl + oy, ox, h - r_bl + oy);
    pb.quad_to(ox - 2.0 * b_left, h / 2.0 + oy, ox, r_tl + oy);
    pb.cubic_to(ox, r_tl - k_tl + oy, r_tl - k_tl + ox, oy, r_tl + ox, oy);
    pb.close();
    pb.to_path()
}

/// Builds the CRT silhouette as a `gsk::Path`, offset by (ox, oy).
/// Mirrors crtPath.js's `build()` step for step so the two are easy to
/// compare by eye. `bulge` is the outward distance a straight edge's own
/// midpoint moves; an edge whose EITHER adjoining corner has radius 0
/// never bulges (not used here -- all 4 corners always share one radius
/// -- but kept for parity with the QML version and in case a future
/// caller needs square corners).
#[allow(clippy::too_many_arguments)]
fn crt_path(w: f32, h: f32, r_tl: f32, r_tr: f32, r_br: f32, r_bl: f32, bulge: f32, ox: f32, oy: f32) -> gsk::Path {
    let b_top = safe_bulge(w - r_tl - r_tr, bulge);
    let b_right = safe_bulge(h - r_tr - r_br, bulge);
    let b_bottom = safe_bulge(w - r_br - r_bl, bulge);
    let b_left = safe_bulge(h - r_bl - r_tl, bulge);
    build_edges(w, h, r_tl, r_tr, r_br, r_bl, b_top, b_right, b_bottom, b_left, ox, oy)
}

mod imp {
    use super::*;
    use std::cell::{Cell, RefCell};

    #[derive(Default)]
    pub struct CrtFrame {
        pub(super) child: RefCell<Option<gtk4::Widget>>,
        pub(super) outer_radius: Cell<f32>,
        pub(super) inner_radius: Cell<f32>,
        pub(super) margin: Cell<f32>,
        pub(super) bulge: Cell<f32>,
    }

    #[glib::object_subclass]
    impl ObjectSubclass for CrtFrame {
        const NAME: &'static str = "BaliseCrtFrame";
        type Type = super::CrtFrame;
        type ParentType = gtk4::Widget;
    }

    impl ObjectImpl for CrtFrame {
        fn dispose(&self) {
            if let Some(child) = self.child.borrow_mut().take() {
                child.unparent();
            }
        }
    }

    impl WidgetImpl for CrtFrame {
        fn measure(&self, orientation: gtk4::Orientation, for_size: i32) -> (i32, i32, i32, i32) {
            if let Some(child) = self.child.borrow().as_ref() {
                child.measure(orientation, for_size)
            } else {
                (0, 0, -1, -1)
            }
        }

        fn size_allocate(&self, width: i32, height: i32, baseline: i32) {
            if let Some(child) = self.child.borrow().as_ref() {
                child.allocate(width, height, baseline, None);
            }
        }

        fn snapshot(&self, snapshot: &gtk4::Snapshot) {
            let w = self.obj().width() as f32;
            let h = self.obj().height() as f32;
            if w <= 0.0 || h <= 0.0 {
                return;
            }

            let r_outer = self.outer_radius.get();
            let r_inner = self.inner_radius.get();
            let margin = self.margin.get();
            let bulge = self.bulge.get();

            // Outer ring: fill with the border gradient, corner-to-corner
            // (135deg, matching balise/style.css's own direction) over
            // this widget's own full bounds.
            let outer = crt_path(w, h, r_outer, r_outer, r_outer, r_outer, bulge, 0.0, 0.0);
            snapshot.push_fill(&outer, gsk::FillRule::Winding);
            let stops: Vec<gsk::ColorStop> = BORDER_STOPS
                .iter()
                .map(|&(offset, r, g, b, a)| gsk::ColorStop::new(offset, gdk::RGBA::new(r, g, b, a)))
                .collect();
            snapshot.append_linear_gradient(
                &graphene::Rect::new(0.0, 0.0, w, h),
                &graphene::Point::new(0.0, 0.0),
                &graphene::Point::new(w, h),
                &stops,
            );
            snapshot.pop();

            // Inner hole: same curve, inset by `margin` on every side --
            // the ring left between this and the outer path above IS the
            // border, same "two nested boxes" idea window.rs's own
            // header comment documents, just curved now instead of a
            // plain inset rect. Each edge's bulge is solved via
            // inset_sagitta() from the OUTER edge's own (safety-clamped)
            // bulge, not just `bulge - margin` -- see that function's own
            // comment for why the naive subtraction thickened the ring
            // at its own peak. Uniform corner radius on all 4 corners
            // (true here, r_outer/r_inner are single values) means top/
            // bottom share one inset value and left/right share another.
            let top_len = w - 2.0 * r_outer;
            let side_len = h - 2.0 * r_outer;
            let outer_top = safe_bulge(top_len, bulge);
            let outer_side = safe_bulge(side_len, bulge);
            let inner_top = inset_sagitta(top_len / 2.0, outer_top, margin);
            let inner_side = inset_sagitta(side_len / 2.0, outer_side, margin);
            let inner = build_edges(
                (w - margin * 2.0).max(0.0),
                (h - margin * 2.0).max(0.0),
                r_inner,
                r_inner,
                r_inner,
                r_inner,
                inner_top,
                inner_side,
                inner_top,
                inner_side,
                margin,
                margin,
            );
            snapshot.push_fill(&inner, gsk::FillRule::Winding);
            if let Some(child) = self.child.borrow().as_ref() {
                self.obj().snapshot_child(child, snapshot);
            }
            snapshot.pop();
        }
    }
}

glib::wrapper! {
    pub struct CrtFrame(ObjectSubclass<imp::CrtFrame>)
        @extends gtk4::Widget,
        @implements gtk4::Accessible, gtk4::Buildable, gtk4::ConstraintTarget;
}

impl Default for CrtFrame {
    fn default() -> Self {
        Self::new()
    }
}

impl CrtFrame {
    /// `outer_radius`/`inner_radius`/`margin` mirror the CSS values this
    /// replaces (`.balise-panel`'s 16px, `.balise-panel-inner`'s 14.5px
    /// and 1.5px margin -- see balise/style.css). `bulge` is the "petit
    /// bend" itself: how far a straight edge's own midpoint bows outward,
    /// same parameter Quickshell's Block.qml/GlassRim.qml expose.
    pub fn new() -> Self {
        let obj: Self = glib::Object::builder().build();
        obj.imp().outer_radius.set(16.0);
        obj.imp().inner_radius.set(14.5);
        obj.imp().margin.set(1.5);
        obj.imp().bulge.set(4.0);
        obj
    }

    pub fn set_child(&self, child: &impl IsA<gtk4::Widget>) {
        if let Some(old) = self.imp().child.borrow_mut().take() {
            old.unparent();
        }
        let widget = child.clone().upcast::<gtk4::Widget>();
        widget.set_parent(self);
        *self.imp().child.borrow_mut() = Some(widget);
    }
}
