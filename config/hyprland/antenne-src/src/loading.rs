//! What the middle of the screen says while nothing plays: a turning ring
//! with what is coming ("Connecting…", "Source 2 of 3"), a small ring alone
//! when a stream waits for the network, or a card when nothing can be
//! played, with its reason and three ways out. The picture behind is dimmed
//! by main.rs (the shade), so a frozen frame never looks like it plays.

use crate::keys::{self, Action};
use gtk4 as gtk;
use gtk::prelude::*;
use gtk::subclass::prelude::*;
use gtk::{gdk, glib, graphene, gsk, pango};
use std::cell::{Cell, RefCell};
use std::rc::Rc;

#[derive(Clone, Copy, PartialEq, Eq, Default)]
pub enum Glyph {
    #[default]
    Ring,
    /// A screen struck through.
    Fail,
}

mod imp {
    use super::*;

    #[derive(Default)]
    pub struct Mark {
        pub glyph: Cell<Glyph>,
        pub angle: Cell<f64>,
        pub ticking: Cell<bool>,
    }

    #[glib::object_subclass]
    impl ObjectSubclass for Mark {
        const NAME: &'static str = "AntenneLoadingMark";
        type Type = super::Mark;
        type ParentType = gtk::Widget;
    }

    impl ObjectImpl for Mark {}

    impl WidgetImpl for Mark {
        fn snapshot(&self, s: &gtk::Snapshot) {
            let w = self.obj();
            let (wd, ht) = (w.width() as f32, w.height() as f32);
            let side = wd.min(ht);
            let ink = gdk::RGBA::new(0.949, 0.949, 0.969, 1.0);
            let dim = gdk::RGBA::new(0.949, 0.949, 0.969, 0.16);
            let stroke = gsk::Stroke::new((side * 0.065).max(2.0));
            stroke.set_line_cap(gsk::LineCap::Round);
            stroke.set_line_join(gsk::LineJoin::Round);
            let (cx, cy) = (wd / 2.0, ht / 2.0);
            match self.glyph.get() {
                Glyph::Ring => {
                    let r = side * 0.42;
                    let track = gsk::PathBuilder::new();
                    track.add_circle(&graphene::Point::new(cx, cy), r);
                    s.append_stroke(&track.to_path(), &stroke, &dim);
                    // a quarter of the circle, turning
                    let a0 = self.angle.get() as f32;
                    let arc = gsk::PathBuilder::new();
                    let p = |a: f32| (cx + r * a.cos(), cy + r * a.sin());
                    let (x0, y0) = p(a0);
                    arc.move_to(x0, y0);
                    let steps = 12;
                    for i in 1..=steps {
                        let (x, y) = p(a0 + std::f32::consts::FRAC_PI_2 * i as f32 / steps as f32);
                        arc.line_to(x, y);
                    }
                    s.append_stroke(&arc.to_path(), &stroke, &ink);
                }
                Glyph::Fail => {
                    let c = gdk::RGBA::new(0.631, 0.631, 0.651, 1.0);
                    let k = side / 48.0;
                    let b = gsk::PathBuilder::new();
                    b.add_rounded_rect(&gsk::RoundedRect::from_rect(graphene::Rect::new(cx - 17.0 * k, cy - 13.0 * k, 34.0 * k, 23.0 * k), 3.5 * k));
                    b.move_to(cx - 6.0 * k, cy + 16.0 * k);
                    b.line_to(cx + 6.0 * k, cy + 16.0 * k);
                    b.move_to(cx - 13.0 * k, cy - 17.0 * k);
                    b.line_to(cx + 13.0 * k, cy + 17.0 * k);
                    s.append_stroke(&b.to_path(), &stroke, &c);
                }
            }
        }
    }
}

glib::wrapper! {
    pub struct Mark(ObjectSubclass<imp::Mark>) @extends gtk::Widget;
}

impl Mark {
    fn set_glyph(&self, g: Glyph) {
        self.imp().glyph.set(g);
        self.queue_draw();
        if g == Glyph::Ring && !self.imp().ticking.replace(true) {
            // turns on the frame clock, and only while it shows
            self.add_tick_callback(|m, clock| {
                let imp = m.imp();
                if imp.glyph.get() != Glyph::Ring || !m.is_mapped() || m.opacity() == 0.0 {
                    imp.ticking.set(false);
                    return glib::ControlFlow::Break;
                }
                let t = clock.frame_time() as f64 / 1e6;
                imp.angle.set((t * std::f64::consts::TAU / 1.1) % std::f64::consts::TAU);
                m.queue_draw();
                glib::ControlFlow::Continue
            });
        }
    }
}

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum State {
    Hidden,
    Loading,
    Buffering,
    Failed,
    /// A question ("Still watching?"): the same card, no glyph.
    Asking,
}

/// A way out of a failure.
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum Choice {
    Retry,
    Back,
    Third,
}

pub struct LoadingView {
    pub root: gtk::Box,
    mark: Mark,
    title: gtk::Label,
    sub: gtk::Label,
    buttons: gtk::Box,
    state: Cell<State>,
    u: f64,
    pub on_choice: Rc<RefCell<Option<Box<dyn Fn(Choice)>>>>,
}

fn label(class: &str) -> gtk::Label {
    let l = gtk::Label::new(None);
    l.add_css_class(class);
    l.set_justify(gtk::Justification::Center);
    l.set_wrap(true);
    l.set_max_width_chars(48);
    l.set_ellipsize(pango::EllipsizeMode::End);
    l.set_lines(2);
    l
}

impl LoadingView {
    pub fn new(u: f64) -> Self {
        let root = gtk::Box::new(gtk::Orientation::Vertical, 0);
        root.add_css_class("loading");
        root.set_halign(gtk::Align::Center);
        root.set_valign(gtk::Align::Center);
        root.set_can_target(false);
        let mark: Mark = glib::Object::new();
        mark.set_halign(gtk::Align::Center);
        let title = label("ldtitle");
        let sub = label("ldsub");
        let buttons = gtk::Box::new(gtk::Orientation::Horizontal, 0);
        buttons.add_css_class("ldbuttons");
        buttons.set_halign(gtk::Align::Center);
        root.append(&mark);
        root.append(&title);
        root.append(&sub);
        root.append(&buttons);
        LoadingView { root, mark, title, sub, buttons, state: Cell::new(State::Hidden), u, on_choice: Rc::default() }
    }

    pub fn state(&self) -> State {
        self.state.get()
    }

    pub fn hide(&self) {
        self.state.set(State::Hidden);
        self.root.remove_css_class("show");
        self.root.set_can_target(false);
    }

    fn show(&self, st: State, glyph: Glyph, size: f64) {
        self.state.set(st);
        let px = (size * self.u).round() as i32;
        self.mark.set_size_request(px, px);
        self.root.add_css_class("show");
        self.root.set_can_target(matches!(st, State::Failed | State::Asking));
        self.mark.set_glyph(glyph);
    }

    /// The ring, what is coming, and how it goes ("Connecting…", "Source 2 of 3").
    pub fn loading(&self, title: &str, sub: &str) {
        self.mark.set_visible(true);
        self.title.set_text(title);
        self.sub.set_text(sub);
        self.title.set_visible(true);
        self.sub.set_visible(!sub.is_empty());
        self.buttons.set_visible(false);
        self.root.remove_css_class("small");
        self.show(State::Loading, Glyph::Ring, 3.4);
    }

    /// A small ring alone: the network is late.
    pub fn buffering(&self) {
        self.mark.set_visible(true);
        self.title.set_visible(false);
        self.sub.set_visible(false);
        self.buttons.set_visible(false);
        self.root.add_css_class("small");
        self.show(State::Buffering, Glyph::Ring, 2.6);
    }

    /// A question, with its answers as buttons (the first is Retry, read
    /// as "go on").
    pub fn ask(&self, title: &str, sub: &str, choices: &[(Choice, String, Action)]) {
        self.failed(title, sub, choices);
        self.state.set(State::Asking);
        self.mark.set_visible(false);
    }

    /// Nothing plays: why, and the ways out (label, key) — the first is Retry,
    /// then Back and a third, when given.
    pub fn failed(&self, title: &str, reason: &str, choices: &[(Choice, String, Action)]) {
        self.mark.set_visible(true);
        self.title.set_text(title);
        self.sub.set_text(reason);
        self.title.set_visible(true);
        self.sub.set_visible(!reason.is_empty());
        while let Some(c) = self.buttons.first_child() {
            self.buttons.remove(&c);
        }
        for (i, (choice, text, key)) in choices.iter().enumerate() {
            let b = gtk::Button::new();
            b.add_css_class("ldbtn");
            if i == 0 {
                b.add_css_class("main");
            }
            b.set_focusable(false);
            let bx = gtk::Box::new(gtk::Orientation::Horizontal, 0);
            let t = gtk::Label::new(Some(text));
            t.add_css_class("ldbtext");
            let k = keys::KeyCap::new(*key);
            k.set_margin_start((0.6 * self.u) as i32);
            bx.append(&t);
            bx.append(&if i == 0 { k.on_light() } else { k });
            b.set_child(Some(&bx));
            let cb = self.on_choice.clone();
            let c = *choice;
            b.connect_clicked(move |_| {
                if let Some(f) = cb.borrow().as_ref() {
                    f(c);
                }
            });
            self.buttons.append(&b);
        }
        self.buttons.set_visible(true);
        self.root.remove_css_class("small");
        self.show(State::Failed, Glyph::Fail, 3.2);
    }
}

/// yt-dlp's error, as one says it: "This video is not available" from
/// YouTube is "YouTube says this video isn't available."
pub fn reason(err: &str, site: &str) -> String {
    let l = err.to_lowercase();
    let site = if site.is_empty() { "The site" } else { site };
    if l.contains("not available") || l.contains("unavailable") {
        if l.contains("country") {
            format!("{site} doesn't offer this video in your country.")
        } else {
            format!("{site} says this video isn't available.")
        }
    } else if l.contains("sign in to confirm your age") || l.contains("age") && l.contains("confirm") {
        format!("{site} asks to sign in to confirm your age.")
    } else if l.contains("private") {
        "This video is private.".into()
    } else if l.contains("removed") || l.contains("deleted") || l.contains("terminated") {
        format!("{site} has removed this video.")
    } else if l.contains("live event will begin") || l.contains("premieres in") {
        "This video hasn't started yet.".into()
    } else if l.contains("sign in") || l.contains("login") || l.contains("members") {
        format!("{site} asks to sign in for this video.")
    } else {
        let e = err.trim();
        let e = e.rsplit_once(": ").map(|(_, r)| r).unwrap_or(e);
        let mut s: String = e.chars().take(90).collect();
        if !s.ends_with('.') {
            s.push('.');
        }
        s
    }
}

#[cfg(test)]
mod tests {
    #[test]
    fn reasons() {
        use super::reason;
        assert_eq!(reason("ERROR: [youtube] zw1eosalOX4: This video is not available", "YouTube"), "YouTube says this video isn't available.");
        assert_eq!(reason("ERROR: [youtube] x: Sign in to confirm your age. This video may be inappropriate", "YouTube"), "YouTube asks to sign in to confirm your age.");
        assert_eq!(reason("ERROR: [youtube] x: Private video", "YouTube"), "This video is private.");
        assert_eq!(reason("ERROR: [generic] x: Unable to download webpage", ""), "Unable to download webpage.");
    }
}
