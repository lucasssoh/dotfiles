//! The live preview: the focused wallpaper in the middle of Prisme's
//! panel, above its caption, with rounded corners. Cross-fades from one
//! picture to the next. main.rs sizes it to a share of the screen.

use gtk4::glib;
use gtk4::prelude::*;
use gtk4::subclass::prelude::*;
use gtk4::{gdk, graphene, gsk};
use std::cell::{Cell, RefCell};

/// Length of the cross-fade between two pictures.
const FADE_MS: f64 = 220.0;

const CORNER_RADIUS: f32 = 14.0;

mod imp {
    use super::*;

    #[derive(Default)]
    pub struct Backdrop {
        pub current: RefCell<Option<gdk::Texture>>,
        /// The picture `current` fades in over, dropped once the fade ends.
        pub previous: RefCell<Option<gdk::Texture>>,
        /// 0 → 1 over a fade, 1 at rest.
        pub fade: Cell<f64>,
        pub fade_start_us: Cell<Option<i64>>,
        pub ticking: Cell<bool>,
    }

    #[glib::object_subclass]
    impl ObjectSubclass for Backdrop {
        const NAME: &'static str = "PrismeBackdrop";
        type Type = super::Backdrop;
        type ParentType = gtk4::Widget;
    }

    impl ObjectImpl for Backdrop {}

    impl WidgetImpl for Backdrop {
        // No size of its own: main.rs sets a size request from the
        // monitor, so nothing here pushes a constraint up to the layer
        // surface.
        fn measure(&self, _orientation: gtk4::Orientation, _for_size: i32) -> (i32, i32, i32, i32) {
            (0, 0, -1, -1)
        }

        fn snapshot(&self, snapshot: &gtk4::Snapshot) {
            let widget = self.obj();
            let (w, h) = (widget.width() as f64, widget.height() as f64);
            if w <= 0.0 || h <= 0.0 {
                return;
            }
            let full = graphene::Rect::new(0.0, 0.0, w as f32, h as f32);
            snapshot.push_rounded_clip(&gsk::RoundedRect::from_rect(full, CORNER_RADIUS));
            let current = self.current.borrow();
            let Some(current) = current.as_ref() else {
                // Nothing decoded yet: a neutral flat fill, like a card's.
                snapshot.append_color(&gdk::RGBA::new(0.11, 0.11, 0.12, 1.0), &full);
                snapshot.pop();
                return;
            };
            let fade = self.fade.get();
            if let (Some(previous), true) = (self.previous.borrow().as_ref(), fade < 1.0) {
                draw_cover(snapshot, previous, w, h);
            }
            snapshot.push_opacity(fade);
            draw_cover(snapshot, current, w, h);
            snapshot.pop();
            snapshot.pop();
        }
    }
}

glib::wrapper! {
    pub struct Backdrop(ObjectSubclass<imp::Backdrop>) @extends gtk4::Widget;
}

impl Backdrop {
    pub fn new() -> Self {
        let backdrop: Self = glib::Object::builder().build();
        backdrop.set_can_target(false);
        backdrop
    }

    /// Shows `texture`, fading in over whatever was there. The same texture
    /// twice is a no-op, so main.rs can re-show freely.
    pub fn show(&self, texture: gdk::Texture) {
        let imp = self.imp();
        if imp.current.borrow().as_ref() == Some(&texture) {
            return;
        }
        let old = imp.current.replace(Some(texture));
        // A fade cut short starts the next one from the picture that was
        // arriving, not from the one before it.
        *imp.previous.borrow_mut() = old;
        imp.fade.set(if imp.previous.borrow().is_some() { 0.0 } else { 1.0 });
        imp.fade_start_us.set(None);
        self.queue_draw();
        if imp.fade.get() < 1.0 && !imp.ticking.replace(true) {
            // Only while fading: at rest the backdrop costs no frame.
            self.add_tick_callback(|backdrop, clock| {
                let imp = backdrop.imp();
                let now = clock.frame_time();
                let start = *imp.fade_start_us.get().get_or_insert(now);
                imp.fade_start_us.set(Some(start));
                let t = ((now - start) as f64 / 1000.0 / FADE_MS).clamp(0.0, 1.0);
                imp.fade.set(t * t * (3.0 - 2.0 * t));
                backdrop.queue_draw();
                if t >= 1.0 {
                    *imp.previous.borrow_mut() = None;
                    imp.ticking.set(false);
                    glib::ControlFlow::Break
                } else {
                    glib::ControlFlow::Continue
                }
            });
        }
    }
}

/// `tex` scaled to cover the w×h preview, centred and cropped.
fn draw_cover(snapshot: &gtk4::Snapshot, tex: &gdk::Texture, w: f64, h: f64) {
    let (tw, th) = (tex.width() as f64, tex.height() as f64);
    let scale = (w / tw).max(h / th).max(0.0001);
    let (dw, dh) = (tw * scale, th * scale);
    let bounds = graphene::Rect::new(((w - dw) / 2.0) as f32, ((h - dh) / 2.0) as f32, dw as f32, dh as f32);
    // Trilinear: the screen-sized picture is drawn at about half its size.
    snapshot.append_scaled_texture(tex, gsk::ScalingFilter::Trilinear, &bounds);
}
