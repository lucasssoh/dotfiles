//! Every key Antenne shows, drawn for what is in hand: a keyboard key, or
//! the gamepad's own button, as the shell's controller popup draws them
//! (quickshell/bar/modules/controller): a round neutral cap with the
//! letter in the brand's colour, softened (A green, B red, Y yellow, X
//! blue on an Xbox pad; PlayStation's shapes; a Switch's swapped letters;
//! four dots, one lit, for a pad nobody knows), and shoulder buttons as
//! trigger caps. The last device used decides; every cap on screen
//! changes at once, and a hint the pad has no button for goes away.

use gtk4 as gtk;
use gtk::prelude::*;
use gtk::subclass::prelude::*;
use gtk::{gdk, glib, graphene, gsk, pango};
use std::cell::{Cell, RefCell};

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum Mode {
    Keyboard,
    Pad,
}

/// What a key does, wherever it is shown.
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum Action {
    Ok,
    Back,
    /// Space: the glance, the sheet, the guide.
    Step,
    Search,
    Settings,
    Keys,
    Info,
    Guide,
    Fav,
    PrevChannel,
    Digits,
    Up,
    Left,
    UpDown,
    LeftRight,
    Arrows,
    PageUpDown,
    Tabs,
    Home,
    More,
    SeekSmall,
    SeekBig,
    FullScreen,
    SuperG,
}

#[derive(Clone, Debug)]
pub(crate) enum Face {
    Letter(&'static str, (f32, f32, f32)),
    Shape(&'static str, (f32, f32, f32)),
    /// A pad without known labels: which dot is lit (n, e, s, w).
    Dots(char),
}

#[derive(Clone, Debug)]
pub(crate) enum Glyph {
    Key(String),
    Face(Face),
    Shoulder(String),
    /// A d-pad, its lit arms: "v", "h" or "a" (all).
    Dpad(char),
}

thread_local! {
    static MODE: Cell<Mode> = const { Cell::new(Mode::Keyboard) };
    static FAMILY: RefCell<String> = RefCell::new("generic".into());
    static CAPS: RefCell<Vec<glib::WeakRef<KeyCap>>> = RefCell::new(vec![]);
    static UNIT: Cell<f64> = const { Cell::new(15.0) };
}

pub fn set_unit(u: f64) {
    UNIT.with(|c| c.set(u));
}

pub fn mode() -> Mode {
    MODE.with(Cell::get)
}

fn refresh_all() {
    CAPS.with(|caps| {
        caps.borrow_mut().retain(|w| w.upgrade().is_some());
        for w in caps.borrow().iter() {
            if let Some(c) = w.upgrade() {
                c.refresh();
            }
        }
    });
}

/// The last device used; every cap follows.
pub fn set_mode(m: Mode) {
    if MODE.with(|c| c.replace(m)) != m {
        refresh_all();
    }
}

/// "xbox", "playstation", "nintendo", "steam" or "generic", from Manette.
pub fn set_family(f: &str) {
    let changed = FAMILY.with(|c| {
        let mut c = c.borrow_mut();
        if *c != f {
            *c = f.to_string();
            true
        } else {
            false
        }
    });
    if changed && mode() == Mode::Pad {
        refresh_all();
    }
}

/// The keyboard's keys for an action.
fn keyboard(a: Action) -> &'static str {
    match a {
        Action::Ok => "Enter",
        Action::Back => "Esc",
        Action::Step => "Space",
        Action::Search => "/",
        Action::Settings => "s",
        Action::Keys => ":",
        Action::Info => "i",
        Action::Guide => "G",
        Action::Fav => "f",
        Action::PrevChannel => "⌫",
        Action::Digits => "0–9",
        Action::Up => "↑",
        Action::Left => "←",
        Action::UpDown => "↑ ↓",
        Action::LeftRight => "← →",
        Action::Arrows => "h j k l",
        Action::PageUpDown => "PgUp PgDn",
        Action::Tabs => "Tab  ⇧Tab",
        Action::Home => "Home",
        Action::More => "m",
        Action::SeekSmall => "← →",
        Action::SeekBig => "⇧ ← →",
        Action::FullScreen => "F11",
        Action::SuperG => "Super G",
    }
}

/// The pad's buttons for an action (none: the hint goes).
fn pad(a: Action, family: &str) -> Vec<Glyph> {
    let tone = |r: f32, g: f32, b: f32| (r / 255.0, g / 255.0, b / 255.0);
    let face = |pos: char| -> Face {
        match family {
            "xbox" => match pos {
                's' => Face::Letter("A", tone(143.0, 212.0, 154.0)),
                'e' => Face::Letter("B", tone(239.0, 143.0, 143.0)),
                'n' => Face::Letter("Y", tone(233.0, 207.0, 125.0)),
                _ => Face::Letter("X", tone(134.0, 174.0, 240.0)),
            },
            "playstation" => match pos {
                's' => Face::Shape("cross", tone(149.0, 184.0, 242.0)),
                'e' => Face::Shape("circle", tone(240.0, 154.0, 164.0)),
                'n' => Face::Shape("triangle", tone(134.0, 214.0, 200.0)),
                _ => Face::Shape("square", tone(231.0, 166.0, 212.0)),
            },
            "nintendo" => Face::Letter(match pos { 's' => "B", 'e' => "A", 'n' => "X", _ => "Y" }, (0.949, 0.949, 0.969)),
            "steam" => Face::Letter(match pos { 's' => "A", 'e' => "B", 'n' => "Y", _ => "X" }, (0.949, 0.949, 0.969)),
            _ => Face::Dots(pos),
        }
    };
    let (lb, rb, lt, rt, select, start) = match family {
        "playstation" => ("L1", "R1", "L2", "R2", "Share", "Options"),
        "nintendo" => ("L", "R", "ZL", "ZR", "−", "+"),
        "steam" => ("L1", "R1", "L2", "R2", "View", "Menu"),
        "xbox" => ("LB", "RB", "LT", "RT", "View", "Menu"),
        _ => ("L", "R", "L2", "R2", "Select", "Start"),
    };
    let sh = |s: &str| Glyph::Shoulder(s.to_string());
    match a {
        Action::Ok => vec![Glyph::Face(face('s'))],
        Action::Back => vec![Glyph::Face(face('e'))],
        Action::Step => vec![Glyph::Face(face('w'))],
        Action::Search => vec![Glyph::Face(face('n'))],
        Action::Keys => vec![sh(select)],
        Action::Settings | Action::More => vec![sh(start)],
        Action::Up => vec![Glyph::Dpad('u')],
        Action::Left => vec![Glyph::Dpad('l')],
        Action::UpDown => vec![Glyph::Dpad('v')],
        Action::LeftRight => vec![Glyph::Dpad('h')],
        Action::Arrows => vec![Glyph::Dpad('a')],
        Action::Tabs | Action::SeekSmall => vec![sh(lb), sh(rb)],
        Action::PageUpDown | Action::SeekBig => vec![sh(lt), sh(rt)],
        _ => vec![],
    }
}

fn glyphs(a: Action) -> Vec<Glyph> {
    match mode() {
        Mode::Keyboard => vec![Glyph::Key(keyboard(a).to_string())],
        Mode::Pad => FAMILY.with(|f| pad(a, &f.borrow())),
    }
}

mod imp {
    use super::*;

    #[derive(Default)]
    pub struct KeyCap {
        pub action: Cell<Option<Action>>,
        /// A cap that hides its parent (the hint's row) when the pad has no button for it.
        pub hides_row: Cell<bool>,
        /// On a light (filled) button: dark ink.
        pub on_light: Cell<bool>,
        pub(crate) glyphs: RefCell<Vec<Glyph>>,
    }

    #[glib::object_subclass]
    impl ObjectSubclass for KeyCap {
        const NAME: &'static str = "AntenneKeyCap";
        type Type = super::KeyCap;
        type ParentType = gtk::Widget;
    }

    impl ObjectImpl for KeyCap {}

    impl WidgetImpl for KeyCap {
        fn measure(&self, o: gtk::Orientation, _for: i32) -> (i32, i32, i32, i32) {
            let obj = self.obj();
            let (w, h) = obj.size();
            let v = if o == gtk::Orientation::Horizontal { w } else { h };
            (v, v, -1, -1)
        }

        fn snapshot(&self, s: &gtk::Snapshot) {
            self.obj().paint(s);
        }
    }
}

glib::wrapper! {
    pub struct KeyCap(ObjectSubclass<imp::KeyCap>) @extends gtk::Widget;
}

impl KeyCap {
    pub fn new(a: Action) -> Self {
        let c: KeyCap = glib::Object::new();
        c.imp().action.set(Some(a));
        c.set_valign(gtk::Align::Center);
        CAPS.with(|caps| caps.borrow_mut().push(c.downgrade()));
        c.refresh();
        c
    }

    /// Drawn for dark text on a light button.
    pub fn on_light(self) -> Self {
        self.imp().on_light.set(true);
        self.queue_draw();
        self
    }

    fn refresh(&self) {
        let Some(a) = self.imp().action.get() else { return };
        let g = glyphs(a);
        let empty = g.is_empty();
        *self.imp().glyphs.borrow_mut() = g;
        self.set_visible(!empty);
        if self.imp().hides_row.get() {
            if let Some(p) = self.parent() {
                p.set_visible(!empty);
            }
        }
        self.queue_resize();
        self.queue_draw();
    }

    fn u() -> f64 {
        UNIT.with(Cell::get)
    }

    fn layout(&self, text: &str, size: f64) -> pango::Layout {
        let l = self.create_pango_layout(Some(text));
        let mut fd = pango::FontDescription::from_string("MiSans Latin");
        fd.set_absolute_size(size * pango::SCALE as f64);
        fd.set_weight(pango::Weight::Bold);
        l.set_font_description(Some(&fd));
        l
    }

    /// Each glyph's width, and the cap's height.
    fn sizes(&self) -> (Vec<f64>, f64) {
        let u = Self::u();
        let h = 1.45 * u;
        let ws = self
            .imp()
            .glyphs
            .borrow()
            .iter()
            .map(|g| match g {
                Glyph::Key(t) => (self.layout(t, 0.78 * u).pixel_size().0 as f64 + 0.9 * u).max(h),
                Glyph::Face(_) | Glyph::Dpad(_) => h,
                Glyph::Shoulder(t) => (self.layout(t, 0.6 * u).pixel_size().0 as f64 + 0.9 * u).max(2.0 * u),
            })
            .collect();
        (ws, h)
    }

    fn size(&self) -> (i32, i32) {
        let (ws, h) = self.sizes();
        let gap = 0.3 * Self::u();
        let w: f64 = ws.iter().sum::<f64>() + gap * ws.len().saturating_sub(1) as f64;
        (w.ceil() as i32, h.ceil() as i32)
    }

    fn paint(&self, s: &gtk::Snapshot) {
        let u = Self::u();
        let (ws, h) = self.sizes();
        let light = self.imp().on_light.get();
        let ink = if light { gdk::RGBA::new(0.05, 0.05, 0.06, 1.0) } else { gdk::RGBA::new(0.949, 0.949, 0.969, 1.0) };
        let ink_a = |a: f32| gdk::RGBA::new(ink.red(), ink.green(), ink.blue(), a);
        let mut x = 0.0f64;
        for (g, w) in self.imp().glyphs.borrow().iter().zip(ws.iter()) {
            let r = graphene::Rect::new(x as f32, 0.0, *w as f32, h as f32);
            match g {
                Glyph::Key(t) => {
                    let rr = gsk::RoundedRect::from_rect(r, (0.32 * u) as f32);
                    s.push_rounded_clip(&rr);
                    s.append_color(&ink_a(0.11), &r);
                    s.pop();
                    s.append_border(&rr, &[1.0; 4], &[ink_a(0.16); 4]);
                    let l = self.layout(t, 0.78 * u);
                    let (tw, th) = l.pixel_size();
                    s.save();
                    s.translate(&graphene::Point::new((x + (w - tw as f64) / 2.0) as f32, ((h - th as f64) / 2.0) as f32));
                    s.append_layout(&l, &ink_a(0.92));
                    s.restore();
                }
                Glyph::Face(f) => {
                    // the cap neutral, the symbol in the button's colour
                    let rr = gsk::RoundedRect::from_rect(r, (h / 2.0) as f32);
                    s.push_rounded_clip(&rr);
                    s.append_color(&ink_a(0.08), &r);
                    s.pop();
                    let (cx, cy) = ((x + w / 2.0) as f32, (h / 2.0) as f32);
                    match f {
                        Face::Letter(t, c) => {
                            let tinted = (c.0, c.1, c.2) != (0.949, 0.949, 0.969);
                            s.append_border(&rr, &[1.2; 4], &[ink_a(if tinted { 0.16 } else { 0.28 }); 4]);
                            let col = if light { ink } else { gdk::RGBA::new(c.0, c.1, c.2, 1.0) };
                            let l = self.layout(t, 0.7 * u);
                            let (tw, th) = l.pixel_size();
                            s.save();
                            s.translate(&graphene::Point::new(cx - tw as f32 / 2.0, cy - th as f32 / 2.0));
                            s.append_layout(&l, &col);
                            s.restore();
                        }
                        Face::Shape(kind, c) => {
                            s.append_border(&rr, &[1.2; 4], &[ink_a(0.16); 4]);
                            let col = if light { ink } else { gdk::RGBA::new(c.0, c.1, c.2, 1.0) };
                            let k = (h as f32 * 0.56) / 24.0;
                            let (ox, oy) = (cx - 12.0 * k, cy - 12.0 * k);
                            let p = |a: f32, b: f32| (ox + a * k, oy + b * k);
                            let b = gsk::PathBuilder::new();
                            match *kind {
                                "cross" => {
                                    let (a, bb) = (p(5.0, 5.0), p(19.0, 19.0));
                                    b.move_to(a.0, a.1);
                                    b.line_to(bb.0, bb.1);
                                    let (a, bb) = (p(19.0, 5.0), p(5.0, 19.0));
                                    b.move_to(a.0, a.1);
                                    b.line_to(bb.0, bb.1);
                                }
                                "square" => b.add_rect(&graphene::Rect::new(ox + 4.5 * k, oy + 4.5 * k, 15.0 * k, 15.0 * k)),
                                "triangle" => {
                                    let (a, bb, c2) = (p(12.0, 3.5), p(21.0, 19.5), p(3.0, 19.5));
                                    b.move_to(a.0, a.1);
                                    b.line_to(bb.0, bb.1);
                                    b.line_to(c2.0, c2.1);
                                    b.close();
                                }
                                _ => b.add_circle(&graphene::Point::new(cx, cy), 8.5 * k),
                            }
                            let st = gsk::Stroke::new((h as f32 * 0.07).max(1.6));
                            st.set_line_cap(gsk::LineCap::Round);
                            st.set_line_join(gsk::LineJoin::Round);
                            s.append_stroke(&b.to_path(), &st, &col);
                        }
                        Face::Dots(pos) => {
                            s.append_border(&rr, &[1.2; 4], &[ink_a(0.28); 4]);
                            let k = h as f32 / 24.0;
                            for (d, dx, dy) in [('n', 12.0, 5.5), ('w', 5.5, 12.0), ('e', 18.5, 12.0), ('s', 12.0, 18.5)] {
                                let rad = 2.7 * k;
                                let dot = graphene::Rect::new(x as f32 + dx * k - rad, dy * k - rad, 2.0 * rad, 2.0 * rad);
                                s.push_rounded_clip(&gsk::RoundedRect::from_rect(dot, rad));
                                s.append_color(&ink_a(if d == *pos { 1.0 } else { 0.18 }), &dot);
                                s.pop();
                            }
                        }
                    }
                }
                Glyph::Shoulder(t) => {
                    // a trigger cap: tighter corners on top than underneath
                    let (t_r, b_r) = ((0.35 * u) as f32, (0.5 * u) as f32);
                    let rr = gsk::RoundedRect::new(r, graphene::Size::new(t_r, t_r), graphene::Size::new(t_r, t_r), graphene::Size::new(b_r, b_r), graphene::Size::new(b_r, b_r));
                    s.append_border(&rr, &[1.2; 4], &[ink_a(0.28); 4]);
                    let l = self.layout(t, 0.6 * u);
                    let (tw, th) = l.pixel_size();
                    s.save();
                    s.translate(&graphene::Point::new((x + (w - tw as f64) / 2.0) as f32, ((h - th as f64) / 2.0) as f32));
                    s.append_layout(&l, &ink_a(0.78));
                    s.restore();
                }
                Glyph::Dpad(lit) => {
                    // a plus, the arms in use lit
                    let k = h as f32 / 24.0;
                    let (cx, cy) = ((x + w / 2.0) as f32, (h / 2.0) as f32);
                    let arm = |dx: f32, dy: f32, on: bool| {
                        let (aw, al) = (6.0 * k, 7.5 * k);
                        let rect = if dx != 0.0 {
                            graphene::Rect::new(if dx > 0.0 { cx + 2.2 * k } else { cx - 2.2 * k - al }, cy - aw / 2.0, al, aw)
                        } else {
                            graphene::Rect::new(cx - aw / 2.0, if dy > 0.0 { cy + 2.2 * k } else { cy - 2.2 * k - al }, aw, al)
                        };
                        s.push_rounded_clip(&gsk::RoundedRect::from_rect(rect, 1.4 * k));
                        s.append_color(&ink_a(if on { 0.92 } else { 0.2 }), &rect);
                        s.pop();
                    };
                    let (up, down, left, right) = match lit {
                        'v' => (true, true, false, false),
                        'h' => (false, false, true, true),
                        'u' => (true, false, false, false),
                        'l' => (false, false, true, false),
                        _ => (true, true, true, true),
                    };
                    arm(0.0, -1.0, up);
                    arm(0.0, 1.0, down);
                    arm(-1.0, 0.0, left);
                    arm(1.0, 0.0, right);
                }
            }
            x += w + 0.3 * u;
        }
    }
}

/// A hint: the cap and what it does, gone with its cap when the pad has
/// no button for it.
pub fn hint(a: Action, text: &str, text_class: &str) -> gtk::Box {
    let row = gtk::Box::new(gtk::Orientation::Horizontal, 0);
    row.add_css_class("khrow");
    let cap = KeyCap::new(a);
    cap.imp().hides_row.set(true);
    cap.set_margin_end((0.8 * KeyCap::u()) as i32);
    let l = gtk::Label::new(Some(text));
    l.add_css_class(text_class);
    l.set_xalign(0.0);
    row.append(&cap);
    row.append(&l);
    cap.refresh();
    row
}
