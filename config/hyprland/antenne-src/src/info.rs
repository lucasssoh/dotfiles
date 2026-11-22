//! The channel, on a dark fade that rises from the bottom left corner, no
//! panel, at two levels. The glance comes by itself (a zap, the pointer, a
//! key that does nothing) and goes after a few seconds: logo, number and
//! name, what is on, what follows. Space (or "i") unfolds it into the
//! sheet, which stays: one line of facts, the next programmes, the
//! sources in the order they are tried.

use crate::keys::{self, Action};
use gtk4 as gtk;
use gtk::prelude::*;
use gtk::{gdk, pango};

pub struct SourceLine {
    pub origin: String,
    pub quality: Option<String>,
    /// Time to answer at the last check, in ms.
    pub ms: Option<u32>,
    pub playing: bool,
    pub dead: bool,
}

pub struct InfoData {
    pub number: u32,
    pub name: String,
    pub logo: Option<(gdk::Texture, bool)>,
    /// Category, quality, country, lists: shown on one line.
    pub facts: Vec<String>,
    /// (title, "10:00 – 10:25", how far it has gone)
    pub now: Option<(String, String, f64)>,
    /// (time, title) of the next ones.
    pub next: Vec<(String, String)>,
    pub sources: Vec<SourceLine>,
    pub favourite: bool,
    /// "Connecting…" or "No source answers", in place of the programme.
    pub status: Option<String>,
    /// A recording: `now` is where it is (time, length) rather than a programme.
    pub playback: bool,
    pub paused: bool,
    /// An episode: ↑ ↓ go to the one before or after.
    pub episode: bool,
}

/// A click on a recording's controls.
pub enum Control {
    Back,
    Toggle,
    Forward,
    Previous,
    Next,
    /// A point on the time bar, 0 to 1.
    SeekTo(f64),
}

type OnControl = std::rc::Rc<std::cell::RefCell<Option<Box<dyn Fn(Control)>>>>;

pub struct InfoView {
    /// The whole window: the fade (it lets clicks through).
    pub root: gtk::Box,
    /// The text and the controls, bottom left: an overlay of its own, so it
    /// takes the clicks over it and only those.
    pub card: gtk::Box,
    u: f64,
    level: std::cell::Cell<u8>,
    /// A recording's time, bar and pause button, updated in place.
    live: std::cell::RefCell<Option<(gtk::Label, gtk::ProgressBar, gtk::Button)>>,
    pub on_control: OnControl,
}

fn label(text: &str, class: &str) -> gtk::Label {
    let l = gtk::Label::new(Some(text));
    l.add_css_class(class);
    l.set_xalign(0.0);
    l.set_ellipsize(pango::EllipsizeMode::End);
    l
}

impl InfoView {
    pub fn new(u: f64) -> Self {
        let root = gtk::Box::new(gtk::Orientation::Vertical, 0);
        root.add_css_class("ifade");
        root.set_can_target(false);
        let card = gtk::Box::new(gtk::Orientation::Vertical, 0);
        card.add_css_class("icard");
        card.set_halign(gtk::Align::Start);
        card.set_valign(gtk::Align::End);
        card.set_size_request((30.0 * u).round() as i32, -1);
        card.set_can_target(false);
        InfoView { root, card, u, level: std::cell::Cell::new(0), live: std::cell::RefCell::new(None), on_control: OnControl::default() }
    }

    /// 0: hidden, 1: the glance, 2: the sheet.
    pub fn set_level(&self, level: u8) {
        self.level.set(level);
        for w in [&self.root, &self.card] {
            if level == 0 {
                w.remove_css_class("show");
            } else {
                w.add_css_class("show");
            }
        }
        self.card.set_can_target(level > 0);
        if level == 1 {
            self.root.add_css_class("light");
        } else if level == 2 {
            self.root.remove_css_class("light");
        }
    }

    pub fn level(&self) -> u8 {
        self.level.get()
    }

    /// The sheet is open (the glance comes and goes on its own).
    pub fn is_open(&self) -> bool {
        self.level.get() == 2
    }

    /// Inside the picture, never astride the black bars: `side` and
    /// `top` are their widths.
    pub fn set_insets(&self, side: i32, top: i32) {
        self.card.set_margin_start(side + (3.2 * self.u).round() as i32);
        self.card.set_margin_bottom(top + (2.4 * self.u).round() as i32);
    }

    /// `full`: the sheet; else the glance.
    /// A recording's time, moved on without drawing the card again (its
    /// buttons keep the pointer).
    pub fn update_playback(&self, time: &str, frac: f64, paused: bool) {
        if let Some((l, bar, b)) = self.live.borrow().as_ref() {
            l.set_text(time);
            bar.set_fraction(frac.clamp(0.0, 1.0));
            b.set_icon_name(if paused { "media-playback-start-symbolic" } else { "media-playback-pause-symbolic" });
        }
    }

    pub fn has_playback(&self) -> bool {
        self.live.borrow().is_some()
    }

    fn control(&self, icon: &str, c: fn() -> Control) -> gtk::Button {
        let b = gtk::Button::from_icon_name(icon);
        b.add_css_class("ictl");
        b.set_focusable(false);
        let cb = self.on_control.clone();
        b.connect_clicked(move |_| {
            if let Some(f) = cb.borrow().as_ref() {
                f(c());
            }
        });
        b
    }

    pub fn fill(&self, d: &InfoData, full: bool) {
        while let Some(c) = self.card.first_child() {
            self.card.remove(&c);
        }
        self.live.borrow_mut().take();
        let plate = gtk::Box::new(gtk::Orientation::Vertical, 0);
        plate.add_css_class("iplate");
        plate.set_halign(gtk::Align::Start);
        plate.set_overflow(gtk::Overflow::Hidden);
        match &d.logo {
            Some((t, light)) => {
                if *light {
                    plate.add_css_class("light");
                }
                plate.append(&crate::guide::logo_picture(t, 2.0 * self.u, self.card.scale_factor()));
            }
            None => {
                let l = gtk::Label::new(Some(&crate::catalog::initials(&d.name)));
                l.add_css_class("sini");
                l.set_vexpand(true);
                plate.append(&l);
            }
        }
        self.card.append(&plate);
        let who = gtk::Box::new(gtk::Orientation::Horizontal, 0);
        who.add_css_class("iwho");
        if d.number != 0 {
            who.append(&label(&d.number.to_string(), "inum"));
        }
        let name = label(&d.name, "iname");
        who.append(&name);
        if d.favourite {
            who.append(&label("★", "istar"));
        }
        self.card.append(&who);
        if full {
            self.card.append(&label(&d.facts.join("   ·   "), "ifacts"));
        }

        if let Some(st) = &d.status {
            self.card.append(&label(st, "istatus"));
        }
        if d.status.is_some() && !d.playback {
        } else if let Some((title, time, frac)) = &d.now {
            let now = gtk::Box::new(gtk::Orientation::Vertical, 0);
            now.add_css_class("inow");
            now.append(&label(title, "ititle"));
            let tl = gtk::Box::new(gtk::Orientation::Horizontal, 0);
            let tlabel = label(time, "itime");
            let bar = gtk::ProgressBar::new();
            bar.add_css_class("ibar");
            bar.set_valign(gtk::Align::Center);
            bar.set_fraction(frac.clamp(0.0, 1.0));
            if d.playback {
                // the time bar: a click goes there
                bar.add_css_class("seek");
                bar.set_hexpand(true);
                let click = gtk::GestureClick::new();
                let cb = self.on_control.clone();
                click.connect_released(move |g, _, x, _| {
                    let w = g.widget().map(|w| w.width()).unwrap_or(1).max(1) as f64;
                    if let Some(f) = cb.borrow().as_ref() {
                        f(Control::SeekTo((x / w).clamp(0.0, 1.0)));
                    }
                });
                bar.add_controller(click);
                tl.append(&bar);
                tl.append(&tlabel);
                now.append(&tl);
                let row = gtk::Box::new(gtk::Orientation::Horizontal, 0);
                row.add_css_class("ictls");
                if d.episode {
                    row.append(&self.control("media-skip-backward-symbolic", || Control::Previous));
                }
                row.append(&self.control("media-seek-backward-symbolic", || Control::Back));
                let toggle = self.control(if d.paused { "media-playback-start-symbolic" } else { "media-playback-pause-symbolic" }, || Control::Toggle);
                toggle.add_css_class("main");
                row.append(&toggle);
                row.append(&self.control("media-seek-forward-symbolic", || Control::Forward));
                if d.episode {
                    row.append(&self.control("media-skip-forward-symbolic", || Control::Next));
                }
                now.append(&row);
                *self.live.borrow_mut() = Some((tlabel, bar.clone(), toggle));
            } else {
                tl.append(&tlabel);
                tl.append(&bar);
                now.append(&tl);
            }
            self.card.append(&now);
        }
        if !d.next.is_empty() && d.status.is_none() {
            let next = gtk::Box::new(gtk::Orientation::Vertical, 0);
            next.add_css_class("inext");
            for (t, title) in d.next.iter().take(if full { 3 } else { 1 }) {
                let r = gtk::Box::new(gtk::Orientation::Horizontal, 0);
                r.append(&label(t, "int"));
                r.append(&label(title, "intl"));
                next.append(&r);
            }
            self.card.append(&next);
        }

        let foot = gtk::Box::new(gtk::Orientation::Horizontal, 0);
        foot.add_css_class("ifoot");
        if !full {
            // a recording: its controls in sight
            foot.append(&keys::hint(Action::Step, "More info", "ikv"));
            self.card.append(&foot);
            return;
        }
        let srcs = gtk::Box::new(gtk::Orientation::Vertical, 0);
        srcs.add_css_class("isrcs");
        srcs.append(&label("SOURCES", "isec"));
        for s in &d.sources {
            let r = gtk::Box::new(gtk::Orientation::Horizontal, 0);
            r.add_css_class("isrc");
            if s.dead {
                r.add_css_class("dead");
            }
            let o = label(&s.origin, "iorigin");
            o.set_hexpand(true);
            r.append(&o);
            if let Some(q) = &s.quality {
                r.append(&label(q, "iq"));
            }
            if s.playing {
                r.append(&label("Playing", "ipill"));
            }
            let t = if s.dead {
                "Not answering".to_string()
            } else {
                s.ms.map(|ms| format!("{:.2} s", ms as f64 / 1000.0)).unwrap_or_else(|| "Not checked yet".into())
            };
            r.append(&label(&t, "it"));
            srcs.append(&r);
        }
        self.card.append(&srcs);
        let hints: Vec<(Action, &str)> = if d.playback {
            vec![(Action::Ok, if d.paused { "Play" } else { "Pause" }), (Action::SeekSmall, "10 s"), (Action::UpDown, if d.episode { "Episode" } else { "Channel" }), (Action::Step, if d.episode { "The show" } else { "Guide" }), (Action::Back, "Close")]
        } else {
            vec![(Action::Step, "Guide"), (Action::Fav, if d.favourite { "Remove from favourites" } else { "Add to favourites" }), (Action::UpDown, "Channel"), (Action::Back, "Close")]
        };
        for (a, v) in hints {
            let h = keys::hint(a, v, "ikv");
            foot.append(&h);
        }
        self.card.append(&foot);
    }
}

/// The next episode, bottom right, while the credits roll: its picture,
/// when it starts, and "Play now" or "Watch credits".
pub struct NextCard {
    pub root: gtk::Box,
    cover: gtk::Box,
    title: gtk::Label,
    when: gtk::Label,
    u: f64,
    /// true: play now; false: watch the credits.
    pub on_choice: std::rc::Rc<std::cell::RefCell<Option<Box<dyn Fn(bool)>>>>,
}

impl NextCard {
    pub fn new(u: f64) -> Self {
        let root = gtk::Box::new(gtk::Orientation::Horizontal, 0);
        root.add_css_class("nextcard");
        root.set_halign(gtk::Align::End);
        root.set_valign(gtk::Align::End);
        root.set_can_target(false);
        let cover = gtk::Box::new(gtk::Orientation::Vertical, 0);
        cover.add_css_class("ncover");
        cover.set_overflow(gtk::Overflow::Hidden);
        cover.set_valign(gtk::Align::Center);
        let w = (9.0 * u).round() as i32;
        cover.set_size_request(w, w * 9 / 16);
        let text = gtk::Box::new(gtk::Orientation::Vertical, 0);
        text.set_valign(gtk::Align::Center);
        text.append(&label("NEXT EPISODE", "nkick"));
        let title = label("", "ntitle");
        title.set_max_width_chars(28);
        text.append(&title);
        let when = label("", "nwhen");
        text.append(&when);
        let row = gtk::Box::new(gtk::Orientation::Horizontal, 0);
        row.add_css_class("nbuttons");
        let on_choice: std::rc::Rc<std::cell::RefCell<Option<Box<dyn Fn(bool)>>>> = Default::default();
        for (i, (t, k)) in [("Play now", Action::Ok), ("Watch credits", Action::Back)].iter().enumerate() {
            let b = gtk::Button::new();
            b.add_css_class("ldbtn");
            if i == 0 {
                b.add_css_class("main");
            }
            b.set_focusable(false);
            let bx = gtk::Box::new(gtk::Orientation::Horizontal, 0);
            bx.append(&label(t, "ldbtext"));
            let cap = keys::KeyCap::new(*k);
            cap.set_margin_start((0.6 * u) as i32);
            bx.append(&if i == 0 { cap.on_light() } else { cap });
            b.set_child(Some(&bx));
            let cb = on_choice.clone();
            let now = i == 0;
            b.connect_clicked(move |_| {
                if let Some(f) = cb.borrow().as_ref() {
                    f(now);
                }
            });
            row.append(&b);
        }
        text.append(&row);
        root.append(&cover);
        root.append(&text);
        NextCard { root, cover, title, when, u, on_choice }
    }

    pub fn show(&self, thumb: Option<gdk::Texture>, initials: &str, title: &str) {
        while let Some(c) = self.cover.first_child() {
            self.cover.remove(&c);
        }
        let w = (9.0 * self.u).round() as i32;
        match thumb {
            Some(t) => {
                let p = gtk::Picture::for_paintable(&t);
                p.set_content_fit(gtk::ContentFit::Cover);
                p.set_size_request(w, w * 9 / 16);
                self.cover.append(&p);
            }
            None => {
                let l = gtk::Label::new(Some(initials));
                l.add_css_class("sini");
                l.set_vexpand(true);
                self.cover.append(&l);
            }
        }
        self.title.set_text(title);
        self.root.add_css_class("show");
        self.root.set_can_target(true);
    }

    pub fn set_when(&self, text: &str) {
        self.when.set_text(text);
    }

    pub fn hide(&self) {
        self.root.remove_css_class("show");
        self.root.set_can_target(false);
    }

    pub fn shown(&self) -> bool {
        self.root.has_css_class("show")
    }

    /// Inside the picture, above the black bars.
    pub fn set_insets(&self, side: i32, top: i32) {
        self.root.set_margin_end(side + (2.4 * self.u).round() as i32);
        self.root.set_margin_bottom(top + (2.4 * self.u).round() as i32);
    }
}
