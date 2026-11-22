//! The guide: the screen split in two. Above, the picture and the
//! programme picked, large, under the channel's logo and name; below, at
//! most half the screen, a column of pages on the left (Channels: Search,
//! Guide; Settings: Countries, My playlists, Checks, Listings, Playback),
//! the page picked on the right. The picked entry is a tab that runs into
//! the page's panel from the side, concave corners and all. The Guide page
//! is the categories as a row of tabs over the grid: channels in rows,
//! time in columns, the past hatched. The other pages are widgets of their
//! own (search.rs, settings.rs), handed to `add_page`.
//!
//! Tabs and grid are one widget that describes what to paint as GTK render
//! nodes, which the GPU draws: nothing is laid out again when it scrolls,
//! nothing is rasterised on the CPU. The picked category is a tab that
//! runs down into the grid's panel, concave corners and all (paths, which
//! CSS cannot give a button); the grid keeps the whole width. Only rows and programmes in view are described;
//! the hour row and the channel column are painted over them, which keeps
//! them in place, and a programme that began before the left edge keeps
//! its title against it. One contour joins the picked channel to the
//! programme picked. Scrolling eases towards a target that later presses
//! retarget, timed on the frame clock, and moves only as much as it takes
//! to keep the selection in view with a row to spare.
//!
//! Every colour and size is in `Theme`, for the visual pass.
//! ANTENNE_DEBUG=1 prints any frame slower than 8 ms to describe.

use crate::epg::{hm, Prog};
use crate::store;
use gtk4 as gtk;
use gtk::prelude::*;
use gtk::subclass::prelude::*;
use gtk::{gdk, glib, graphene, gsk, pango};
use std::cell::{Cell, RefCell};
use std::collections::{HashMap, HashSet};
use std::rc::{Rc, Weak};

/// Colours as (r, g, b); sizes in units (see main.rs).
struct Theme;
impl Theme {
    const INK: (f32, f32, f32) = (0.949, 0.949, 0.969);
    const TEXT_DIM: (f32, f32, f32) = (0.631, 0.631, 0.651);
    const TEXT_FAINT: (f32, f32, f32) = (0.486, 0.486, 0.502);
    const BG: (f32, f32, f32) = (0.0, 0.0, 0.0);
    const PANEL: (f32, f32, f32) = (0.086, 0.086, 0.098);
    const LIGHT_PLATE: (f32, f32, f32) = (0.914, 0.902, 0.875);
    /// Cells are painted opaque (the panel with this much ink mixed in), so
    /// the now line runs behind them and never through a title.
    const CELL: f32 = 0.06;
    const CELL_LIVE: f32 = 0.10;
    /// What is already past, left of now: a veil and diagonal hatching
    /// over the cells, under their text.
    const PAST_VEIL: f32 = 0.45;
    const HATCH: f32 = 0.055;
    /// Hatching period, in units.
    const HATCH_STEP: f64 = 0.5;
    const CELL_PICKED: f32 = 0.20;
    const CELL_EMPTY: f32 = 0.025;
    const CONTOUR: f32 = 0.92;
    const RULE: f32 = 0.05;
    /// The row of tabs over the grid, and the space either side of a name.
    const TAB_BAR: f64 = 2.4;
    const TAB_PAD: f64 = 1.0;
    const TAB_R: f64 = 0.8;
    const ROW: f64 = 2.6;
    const COLUMN: f64 = 11.0;
    const HOURS: f64 = 1.6;
    /// Units per minute of programme.
    const PER_MIN: f64 = 0.30;
    const RADIUS: f32 = 0.5;
    const LOGO: f64 = 1.7;
    const HEAD_LOGO: f64 = 2.6;
    const TEXT: f64 = 0.82;
    const SMALL: f64 = 0.72;
    /// Fraction of the remaining distance covered per 1/60 s of scrolling.
    const EASE: f64 = 0.38;
    /// The column of pages: its width, an entry's height, the room a
    /// section's name takes above its first entry, and the space left
    /// right of an entry that is not picked.
    const NAV_W: f64 = 15.5;
    const ENTRY: f64 = 2.85;
    const SECTION: f64 = 2.6;
    /// Entries sit this far right of their section's name.
    const INDENT: f64 = 1.1;
    const NAV_GAP: f64 = 1.2;
    const HOVER: f32 = 0.05;
}

/// The pages of the column, in order.
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum Page {
    Search,
    Guide,
    Continue,
    Shows,
    Countries,
    Playlists,
    Checks,
    Listings,
    Playback,
}

impl Page {
    pub const ALL: [Page; 9] = [Page::Search, Page::Guide, Page::Continue, Page::Shows, Page::Countries, Page::Playlists, Page::Checks, Page::Listings, Page::Playback];

    pub fn title(self) -> &'static str {
        match self {
            Page::Search => "Search",
            Page::Guide => "Guide",
            Page::Continue => "Continue watching",
            Page::Shows => "Shows",
            Page::Countries => "Countries",
            Page::Playlists => "My sources",
            Page::Checks => "Channel checks",
            Page::Listings => "TV listings",
            Page::Playback => "Playback",
        }
    }

    /// The section that begins with this page (Search stands alone, above).
    fn section(self) -> Option<&'static str> {
        match self {
            Page::Guide => Some("TV"),
            Page::Continue => Some("STREAMING"),
            Page::Countries => Some("SETTINGS"),
            _ => None,
        }
    }

    pub fn is_settings(self) -> bool {
        !matches!(self, Page::Search | Page::Guide | Page::Continue | Page::Shows)
    }

    pub fn is_library(self) -> bool {
        matches!(self, Page::Continue | Page::Shows)
    }

    pub fn index(self) -> usize {
        Self::ALL.iter().position(|p| *p == self).unwrap_or(1)
    }
}

/// The column: the page picked, whether it has the keyboard, the entry
/// under the pointer, and what each entry says under its name.
struct NavSt {
    sel: usize,
    focus: bool,
    hover: Option<usize>,
    summaries: Vec<String>,
}

fn rgba(c: (f32, f32, f32), a: f32) -> gdk::RGBA {
    gdk::RGBA::new(c.0, c.1, c.2, a)
}

/// The panel with `k` of ink mixed in, opaque.
fn mix(k: f32) -> gdk::RGBA {
    let (p, i) = (Theme::PANEL, Theme::INK);
    gdk::RGBA::new(p.0 + (i.0 - p.0) * k, p.1 + (i.1 - p.1) * k, p.2 + (i.2 - p.2) * k, 1.0)
}

fn rect(x: f64, y: f64, w: f64, h: f64) -> graphene::Rect {
    graphene::Rect::new(x as f32, y as f32, w as f32, h as f32)
}

fn size(r: f64) -> graphene::Size {
    graphene::Size::new(r as f32, r as f32)
}

/// What the header shows for a show or an episode, in place of the
/// programme picked in the grid.
pub struct Head {
    pub logo: Option<gdk::Texture>,
    pub initials: String,
    pub line: String,
    pub title: String,
    pub time: String,
    pub bar: Option<f64>,
    /// The main action, as a pill ("▶  Resume · Arc · E7"); empty: none.
    pub action: String,
    /// Enter does it (its key shows on the pill).
    pub action_key: bool,
    /// A second, quieter one, on Home ("↺  From the beginning").
    pub action2: String,
    /// "More actions" on its key.
    pub more: bool,
    /// Lines under it, in Pango markup (empty: none).
    pub desc: String,
}

pub struct RowData {
    pub key: String,
    pub number: u32,
    pub name: String,
    pub progs: Vec<Prog>,
}

struct St {
    rows: Vec<RowData>,
    cats: Vec<(String, usize)>,
    cat: usize,
    playing: Option<String>,
    sel: usize,
    /// The time cursor: the selected programme is the one running then.
    tc: i64,
    w0: i64,
    w1: i64,
    cats_focus: bool,
    sx: f64,
    sy: f64,
    tx: f64,
    ty: f64,
    /// The tabs' own (horizontal) scroll, and their total width.
    cx: f64,
    ctx: f64,
    tabs_w: f64,
    pointer: (f64, f64),
    last_frame: i64,
}

mod imp {
    use super::*;

    #[derive(Default)]
    pub struct Grid {
        pub view: RefCell<Weak<GuideView>>,
    }

    #[glib::object_subclass]
    impl ObjectSubclass for Grid {
        const NAME: &'static str = "AntenneGuideGrid";
        type Type = super::Grid;
        type ParentType = gtk::Widget;
    }

    impl ObjectImpl for Grid {}

    impl WidgetImpl for Grid {
        fn snapshot(&self, s: &gtk::Snapshot) {
            let w = self.obj();
            if let Some(v) = self.view.borrow().upgrade() {
                v.paint(s, w.width() as f64, w.height() as f64);
            }
        }
    }
}

glib::wrapper! {
    pub struct Grid(ObjectSubclass<imp::Grid>) @extends gtk::Widget;
}

mod nav_imp {
    use super::*;

    #[derive(Default)]
    pub struct Nav {
        pub view: RefCell<Weak<GuideView>>,
    }

    #[glib::object_subclass]
    impl ObjectSubclass for Nav {
        const NAME: &'static str = "AntenneGuideNav";
        type Type = super::Nav;
        type ParentType = gtk::Widget;
    }

    impl ObjectImpl for Nav {}

    impl WidgetImpl for Nav {
        fn snapshot(&self, s: &gtk::Snapshot) {
            let w = self.obj();
            if let Some(v) = self.view.borrow().upgrade() {
                v.paint_nav(s, w.width() as f64, w.height() as f64);
            }
        }
    }
}

glib::wrapper! {
    pub struct Nav(ObjectSubclass<nav_imp::Nav>) @extends gtk::Widget;
}

mod logo_imp {
    use super::*;

    #[derive(Default)]
    pub struct LogoPic {
        pub tex: RefCell<Option<gdk::Texture>>,
        pub size: Cell<(i32, i32)>,
    }

    #[glib::object_subclass]
    impl ObjectSubclass for LogoPic {
        const NAME: &'static str = "AntenneLogo";
        type Type = super::LogoPic;
        type ParentType = gtk::Widget;
    }

    impl ObjectImpl for LogoPic {}

    impl WidgetImpl for LogoPic {
        // the same size whatever the room: a logo never grows into blur
        fn measure(&self, o: gtk::Orientation, _for: i32) -> (i32, i32, i32, i32) {
            let (w, h) = self.size.get();
            let v = if o == gtk::Orientation::Horizontal { w } else { h };
            (v, v, -1, -1)
        }

        fn snapshot(&self, s: &gtk::Snapshot) {
            if let Some(t) = self.tex.borrow().as_ref() {
                let (w, h) = self.size.get();
                s.append_scaled_texture(t, gsk::ScalingFilter::Trilinear, &rect(0.0, 0.0, w as f64, h as f64));
            }
        }
    }
}

glib::wrapper! {
    pub struct LogoPic(ObjectSubclass<logo_imp::LogoPic>) @extends gtk::Widget;
}

/// A decoded logo at the size it was decoded to (`scale`: the display's),
/// or smaller to fit `max_h` pixels; never enlarged.
pub fn logo_picture(t: &gdk::Texture, max_h: f64, scale: i32) -> LogoPic {
    let s = scale.max(1) as f64;
    let (w, h) = (t.width() as f64 / s, t.height() as f64 / s);
    let k = if h > max_h { max_h / h } else { 1.0 };
    let p: LogoPic = glib::Object::new();
    *p.imp().tex.borrow_mut() = Some(t.clone());
    p.imp().size.set(((w * k).round().max(1.0) as i32, (h * k).round().max(1.0) as i32));
    p.set_halign(gtk::Align::Center);
    p.set_valign(gtk::Align::Center);
    p
}

pub struct GuideView {
    pub root: gtk::Box,
    u: f64,
    head: gtk::Box,
    pip: gtk::Box,
    head_plate: gtk::Box,
    head_logo: gtk::Picture,
    head_ini: gtk::Label,
    pip_label: gtk::Label,
    head_ch: gtk::Label,
    clock: gtk::Label,
    head_title: gtk::Label,
    head_time: gtk::Label,
    head_bar: gtk::ProgressBar,
    head_remind: gtk::Label,
    /// "Remind me" or "Remove", on Enter (or A).
    head_remind_key: gtk::Box,
    head_desc: gtk::Label,
    head_next: gtk::Label,
    head_action: gtk::Label,
    head_action2: gtk::Label,
    head_pill: gtk::Box,
    head_pill2: gtk::Box,
    head_key: crate::keys::KeyCap,
    head_more: gtk::Box,
    custom: Cell<bool>,
    grid: Grid,
    nav: Nav,
    stack: gtk::Stack,
    navst: RefCell<NavSt>,
    st: RefCell<St>,
    animating: Cell<bool>,
    this: RefCell<Weak<GuideView>>,
    logos: RefCell<HashMap<String, (gdk::Texture, bool)>>,
    reminders: RefCell<HashSet<(String, i64)>>,
    layouts: RefCell<HashMap<(String, i32, u8), pango::Layout>>,
    fonts: Vec<pango::FontDescription>,
    debug: bool,
    pub on_play: RefCell<Option<Box<dyn Fn(String)>>>,
    pub on_category: RefCell<Option<Box<dyn Fn(String)>>>,
    pub on_visible: RefCell<Option<Box<dyn Fn(Vec<String>)>>>,
    /// An entry of the column clicked.
    pub on_nav: RefCell<Option<Box<dyn Fn(Page)>>>,
    /// The keyboard went to the menu (true) or to the page.
    pub on_focus: RefCell<Option<Box<dyn Fn(bool)>>>,
}

const F_TEXT: u8 = 0;
const F_TEXT_BOLD: u8 = 1;
const F_SMALL: u8 = 2;
const F_NAME: u8 = 3;
const F_INI: u8 = 4;
const F_TAB: u8 = 5;
const F_LABEL: u8 = 6;

impl GuideView {
    pub fn new(u: f64) -> Rc<Self> {
        let root = gtk::Box::new(gtk::Orientation::Vertical, 0);
        root.add_css_class("guide");
        root.set_can_target(false);

        let head = gtk::Box::new(gtk::Orientation::Horizontal, 0);
        head.add_css_class("ghead");
        let info = gtk::Box::new(gtk::Orientation::Vertical, 0);
        info.add_css_class("ginfo");
        info.set_hexpand(true);
        info.set_valign(gtk::Align::Center);
        let label = |class: &str| {
            let l = gtk::Label::new(None);
            l.add_css_class(class);
            l.set_xalign(0.0);
            l
        };
        // the channel: its logo on a plate, its number and name, the clock
        let line = gtk::Box::new(gtk::Orientation::Horizontal, 0);
        line.add_css_class("gline");
        // The plate is always there, with initials until the logo arrives,
        // so the line never shifts. Nothing in the header may ask to expand
        // vertically: GTK passes that up, and the header would take the
        // grid's half.
        let head_plate = gtk::Box::new(gtk::Orientation::Vertical, 0);
        head_plate.add_css_class("hplate");
        head_plate.set_valign(gtk::Align::Center);
        head_plate.set_overflow(gtk::Overflow::Hidden);
        let side = (Theme::HEAD_LOGO * u).round() as i32;
        let inner = ((Theme::HEAD_LOGO - 0.6) * u).round() as i32;
        let head_logo = gtk::Picture::new();
        head_logo.set_content_fit(gtk::ContentFit::Contain);
        head_logo.set_can_shrink(true);
        head_logo.set_halign(gtk::Align::Center);
        head_logo.set_valign(gtk::Align::Center);
        let head_ini = gtk::Label::new(None);
        head_ini.add_css_class("hini");
        head_ini.set_size_request(inner, inner);
        head_plate.append(&head_logo);
        head_plate.append(&head_ini);
        head_plate.set_size_request(side, side);
        let head_ch = label("gch");
        head_ch.set_hexpand(true);
        head_ch.set_valign(gtk::Align::Center);
        let clock = label("gclock");
        clock.set_valign(gtk::Align::Center);
        line.append(&head_plate);
        line.append(&head_ch);
        line.append(&clock);
        let head_title = label("gtitle");
        head_title.set_wrap(true);
        head_title.set_lines(2);
        head_title.set_ellipsize(pango::EllipsizeMode::End);
        let trow = gtk::Box::new(gtk::Orientation::Horizontal, 0);
        let head_time = label("gtime");
        let head_bar = gtk::ProgressBar::new();
        head_bar.add_css_class("gbar");
        head_bar.set_valign(gtk::Align::Center);
        let head_remind = label("gremind");
        trow.append(&head_time);
        trow.append(&head_bar);
        trow.append(&head_remind);
        let head_remind_key = crate::keys::hint(crate::keys::Action::Ok, "Remind me", "gremind");
        head_remind_key.add_css_class("gremkey");
        trow.append(&head_remind_key);
        let head_desc = label("gdesc");
        head_desc.set_wrap(true);
        head_desc.set_lines(4);
        head_desc.set_ellipsize(pango::EllipsizeMode::End);
        head_desc.set_max_width_chars(70);
        let head_next = label("gnext");
        head_next.set_ellipsize(pango::EllipsizeMode::End);
        let head_action = label("gactext");
        let head_action2 = label("gactext");
        let head_pill = gtk::Box::new(gtk::Orientation::Horizontal, 0);
        head_pill.add_css_class("gaction");
        head_pill.append(&head_action);
        let head_key = crate::keys::KeyCap::new(crate::keys::Action::Ok).on_light();
        head_key.set_margin_start((0.7 * u) as i32);
        head_pill.append(&head_key);
        head_pill.set_visible(false);
        let head_pill2 = crate::keys::hint(crate::keys::Action::Home, "", "gactext");
        head_pill2.add_css_class("gaction2");
        if let Some(l) = head_pill2.last_child() {
            head_pill2.remove(&l);
        }
        head_pill2.prepend(&head_action2);
        head_action2.set_margin_end((0.7 * u) as i32);
        let head_more = crate::keys::hint(crate::keys::Action::More, "More actions", "gnext");
        head_more.set_halign(gtk::Align::Start);
        let actions = gtk::Box::new(gtk::Orientation::Horizontal, 0);
        actions.set_halign(gtk::Align::Start);
        actions.append(&head_pill);
        actions.append(&head_pill2);
        info.append(&line);
        info.append(&head_title);
        info.append(&trow);
        info.append(&head_desc);
        info.append(&head_next);
        info.append(&actions);
        info.append(&head_more);
        // Over the picture: what it is showing, or that it is connecting.
        let pip = gtk::Box::new(gtk::Orientation::Vertical, 0);
        pip.add_css_class("pipslot");
        pip.set_valign(gtk::Align::Start);
        let pip_label = gtk::Label::new(None);
        pip_label.add_css_class("piplabel");
        pip_label.set_halign(gtk::Align::Start);
        pip_label.set_valign(gtk::Align::Start);
        pip.append(&pip_label);
        head.append(&info);
        head.append(&pip);
        head.set_vexpand(false);

        let grid: Grid = glib::Object::new();
        grid.set_hexpand(true);
        grid.set_vexpand(true);
        grid.set_overflow(gtk::Overflow::Hidden);
        let nav: Nav = glib::Object::new();
        nav.set_size_request((Theme::NAV_W * u).round() as i32, -1);
        nav.set_vexpand(true);
        let stack = gtk::Stack::new();
        stack.set_hexpand(true);
        stack.set_vexpand(true);
        stack.set_transition_type(gtk::StackTransitionType::None);
        stack.add_named(&grid, Some("guide"));
        let lower = gtk::Box::new(gtk::Orientation::Horizontal, 0);
        lower.set_vexpand(true);
        lower.append(&nav);
        lower.append(&stack);
        root.append(&head);
        root.append(&lower);

        let font = |sz: f64, w: pango::Weight| {
            let mut fd = pango::FontDescription::from_string("MiSans Latin");
            fd.set_absolute_size(sz * u * pango::SCALE as f64);
            fd.set_weight(w);
            fd
        };
        let fonts = vec![
            font(Theme::TEXT, pango::Weight::Normal),
            font(Theme::TEXT, pango::Weight::Medium),
            font(Theme::SMALL, pango::Weight::Normal),
            font(0.86, pango::Weight::Medium),
            font(0.62, pango::Weight::Semibold),
            font(0.88, pango::Weight::Medium),
            font(0.72, pango::Weight::Medium),
        ];

        let now = store::now() as i64;
        let me = Rc::new(GuideView {
            root,
            u,
            head,
            pip,
            head_plate,
            head_logo,
            head_ini,
            pip_label,
            head_ch,
            clock,
            head_title,
            head_time,
            head_bar,
            head_remind,
            head_remind_key: head_remind_key.clone(),
            head_desc,
            head_next,
            head_action,
            head_action2,
            head_pill,
            head_pill2,
            head_key,
            head_more,
            custom: Cell::new(false),
            grid: grid.clone(),
            nav: nav.clone(),
            stack,
            navst: RefCell::new(NavSt { sel: 1, focus: false, hover: None, summaries: vec![String::new(); Page::ALL.len()] }),
            st: RefCell::new(St {
                rows: vec![],
                cats: vec![],
                cat: 0,
                playing: None,
                sel: 0,
                tc: now,
                w0: now,
                w1: now + 3600,
                cats_focus: false,
                sx: 0.0,
                sy: 0.0,
                tx: 0.0,
                ty: 0.0,
                cx: 0.0,
                ctx: 0.0,
                tabs_w: 0.0,
                pointer: (0.0, 0.0),
                last_frame: 0,
            }),
            animating: Cell::new(false),
            this: RefCell::new(Weak::new()),
            logos: RefCell::new(HashMap::new()),
            reminders: RefCell::new(HashSet::new()),
            layouts: RefCell::new(HashMap::new()),
            fonts,
            debug: std::env::var_os("ANTENNE_DEBUG").is_some(),
            on_play: RefCell::new(None),
            on_category: RefCell::new(None),
            on_visible: RefCell::new(None),
            on_nav: RefCell::new(None),
            on_focus: RefCell::new(None),
        });
        *me.this.borrow_mut() = Rc::downgrade(&me);
        *grid.imp().view.borrow_mut() = Rc::downgrade(&me);
        *nav.imp().view.borrow_mut() = Rc::downgrade(&me);

        // the column: hover, and a click picks the page
        let motion = gtk::EventControllerMotion::new();
        let w = Rc::downgrade(&me);
        motion.connect_motion(move |_, _, y| {
            if let Some(me) = w.upgrade() {
                let h = me.nav_hit(y);
                if me.navst.borrow().hover != h {
                    me.navst.borrow_mut().hover = h;
                    me.nav.queue_draw();
                }
            }
        });
        let w = Rc::downgrade(&me);
        motion.connect_leave(move |_| {
            if let Some(me) = w.upgrade() {
                me.navst.borrow_mut().hover = None;
                me.nav.queue_draw();
            }
        });
        nav.add_controller(motion);
        let click = gtk::GestureClick::new();
        let w = Rc::downgrade(&me);
        click.connect_pressed(move |_, _, _, y| {
            if let Some(me) = w.upgrade() {
                if let Some(i) = me.nav_hit(y) {
                    if let Some(f) = me.on_nav.borrow().as_ref() {
                        f(Page::ALL[i]);
                    }
                }
            }
        });
        nav.add_controller(click);

        let motion = gtk::EventControllerMotion::new();
        let w = Rc::downgrade(&me);
        motion.connect_motion(move |_, x, y| {
            if let Some(me) = w.upgrade() {
                me.st.borrow_mut().pointer = (x, y);
            }
        });
        grid.add_controller(motion);
        // Wheel: over the tabs, the tabs; over the hour row, through time;
        // elsewhere, the rows.
        let wheel = gtk::EventControllerScroll::new(gtk::EventControllerScrollFlags::BOTH_AXES);
        let w = Rc::downgrade(&me);
        wheel.connect_scroll(move |c, dx, dy| {
            let Some(me) = w.upgrade() else { return glib::Propagation::Proceed };
            let u = me.u;
            let step = if c.unit() == gdk::ScrollUnit::Wheel { u * Theme::ROW * 1.5 } else { 1.0 };
            {
                let mut st = me.st.borrow_mut();
                let (_, py) = st.pointer;
                let top = u * Theme::TAB_BAR;
                if py < top {
                    st.ctx += (dx + dy) * step;
                } else if py < top + u * Theme::HOURS && dx == 0.0 {
                    st.tx += dy * step;
                } else {
                    st.tx += dx * step;
                    st.ty += dy * step;
                }
            }
            me.clamp_targets();
            me.animate();
            glib::Propagation::Stop
        });
        grid.add_controller(wheel);
        let click = gtk::GestureClick::new();
        let w = Rc::downgrade(&me);
        click.connect_pressed(move |_, _, x, y| {
            if let Some(me) = w.upgrade() {
                me.click(x, y);
            }
        });
        grid.add_controller(click);
        me
    }

    fn per_s(&self) -> f64 {
        self.u * Theme::PER_MIN / 60.0
    }

    /// The grid now has the whole width; the tabs sit above it.
    fn left(&self) -> f64 {
        0.0
    }

    fn top(&self) -> f64 {
        self.u * Theme::TAB_BAR
    }

    fn tab_label(name: &str) -> String {
        if name == "Favourites" { "★  Favourites".to_string() } else { name.to_string() }
    }

    /// Each tab's (x, width) along the row, before scrolling.
    fn tab_geom(&self, cats: &[(String, usize)]) -> Vec<(f64, f64)> {
        let u = self.u;
        // the first tab flush with the panel's left edge, which it continues
        // (the column's entries run into that edge from the side)
        let mut x = 0.0;
        let mut out = Vec::with_capacity(cats.len());
        for (name, n) in cats {
            let nw = self.layout(&Self::tab_label(name), 30.0 * u, F_TAB).pixel_size().0 as f64;
            let cw = self.layout(&n.to_string(), 4.0 * u, F_SMALL).pixel_size().0 as f64;
            let w = 2.0 * Theme::TAB_PAD * u + nw + 0.55 * u + cw;
            out.push((x, w));
            x += w + 0.15 * u;
        }
        out
    }

    /// True when the first channel is picked: ↑ then goes to the tabs.
    pub fn at_first_row(&self) -> bool {
        self.st.borrow().sel == 0
    }

    /// The box logos are decoded to, in device pixels: the header's, which
    /// is the largest they are shown (as tall as the plate's inside, up to
    /// three times as wide).
    pub fn logo_box(&self) -> (u32, u32) {
        let px = (Theme::HEAD_LOGO - 0.6) * self.u * self.grid.scale_factor().max(1) as f64;
        ((px * 3.0).round().max(8.0) as u32, px.round().max(8.0) as u32)
    }

    /// The split: the header takes the top of a `height`-tall window, the
    /// grid the rest, never more than half. Returns the picture's size.
    pub fn split(&self, width: i32, height: i32) -> (i32, i32) {
        let u = self.u;
        let head_h = (height as f64 * 0.5 - 2.4 * u).max(8.0 * u);
        let mut pw = head_h * 16.0 / 9.0;
        let max_w = width as f64 * 0.62;
        if pw > max_w {
            pw = max_w;
        }
        let ph = pw * 9.0 / 16.0;
        self.head.set_size_request(-1, head_h.round() as i32);
        self.pip.set_size_request(pw.round() as i32, ph.round() as i32);
        (pw.round() as i32, ph.round() as i32)
    }

    // ---- the column of pages ------------------------------------------------

    /// A page's widget, shown when its entry is picked: "search" for
    /// Search, "settings" for every settings page.
    pub fn add_page(&self, name: &str, widget: &impl IsA<gtk::Widget>) {
        self.stack.add_named(widget, Some(name));
    }

    pub fn page(&self) -> Page {
        Page::ALL[self.navst.borrow().sel]
    }

    pub fn set_page(&self, p: Page) {
        self.navst.borrow_mut().sel = p.index();
        self.stack.set_visible_child_name(match p {
            Page::Search => "search",
            Page::Guide => "guide",
            Page::Continue | Page::Shows => "library",
            _ => "settings",
        });
        self.nav.queue_draw();
        self.grid.queue_draw();
    }

    /// The next or previous page.
    pub fn move_nav(&self, d: i32) -> Page {
        let i = (self.navst.borrow().sel as i32 + d).clamp(0, Page::ALL.len() as i32 - 1) as usize;
        self.set_page(Page::ALL[i]);
        Page::ALL[i]
    }

    /// The column has the keyboard (a bar beside the entry picked), or the
    /// page has it.
    pub fn set_nav_focus(&self, on: bool) {
        self.navst.borrow_mut().focus = on;
        self.nav.queue_draw();
        self.grid.queue_draw();
        if let Some(f) = self.on_focus.borrow().as_ref() {
            f(on);
        }
    }

    pub fn nav_focus(&self) -> bool {
        self.navst.borrow().focus
    }

    /// What each entry says under its name, in `Page::ALL` order.
    pub fn set_summaries(&self, s: Vec<String>) {
        if self.navst.borrow().summaries != s {
            self.navst.borrow_mut().summaries = s;
            self.nav.queue_draw();
        }
    }

    /// Each entry's top.
    fn nav_geom(&self) -> Vec<f64> {
        let u = self.u;
        let mut y = u * Theme::TAB_BAR;
        let mut out = Vec::with_capacity(Page::ALL.len());
        for (i, p) in Page::ALL.iter().enumerate() {
            if i > 0 && p.section().is_some() {
                y += u * Theme::SECTION;
            }
            out.push(y);
            y += u * Theme::ENTRY;
        }
        out
    }

    fn nav_hit(&self, y: f64) -> Option<usize> {
        let e = self.u * Theme::ENTRY;
        self.nav_geom().iter().position(|&t| y >= t && y < t + e)
    }

    // ---- data ------------------------------------------------------------

    pub fn set_rows(&self, rows: Vec<RowData>, select: Option<&str>, playing: Option<&str>, keep_time: bool) {
        let now = store::now() as i64;
        let per_s = self.per_s();
        let u = self.u;
        let page = (self.grid.height() as f64 - u * (Theme::TAB_BAR + Theme::HOURS)).max(u * Theme::ROW);
        {
            let mut st = self.st.borrow_mut();
            let fresh = !keep_time || st.rows.is_empty();
            st.rows = rows;
            st.playing = playing.map(str::to_string);
            st.sel = select.and_then(|k| st.rows.iter().position(|r| r.key == k)).unwrap_or(0);
            st.w0 = (now - 3600) / 1800 * 1800;
            st.w1 = st.w0 + 9 * 3600;
            if fresh {
                st.tc = now;
                st.tx = ((now - st.w0) as f64 * per_s - 4.0 * u).max(0.0);
            }
            st.ty = (st.sel as f64 * u * Theme::ROW - page / 2.0 + u * Theme::ROW / 2.0).max(0.0);
        }
        self.layouts.borrow_mut().clear();
        self.clamp_targets();
        {
            let mut st = self.st.borrow_mut();
            st.sx = st.tx;
            st.sy = st.ty;
        }
        self.update_head();
        self.grid.queue_draw();
        self.report_visible();
    }

    /// The tabs: (name, number of channels), and the one picked, kept in
    /// view with some room to spare on either side.
    pub fn set_categories(&self, cats: Vec<(String, usize)>, current: &str) {
        let u = self.u;
        let aw = self.grid.width() as f64;
        let geom = self.tab_geom(&cats);
        {
            let mut st = self.st.borrow_mut();
            st.cat = cats.iter().position(|(c, _)| c == current).unwrap_or(0);
            st.tabs_w = geom.last().map(|(x, w)| x + w + Theme::TAB_R * u + 0.2 * u).unwrap_or(0.0);
            if let Some(&(x, w)) = geom.get(st.cat) {
                let spare = 3.0 * u;
                if x - spare < st.ctx {
                    st.ctx = x - spare;
                } else if x + w + spare > st.ctx + aw {
                    st.ctx = x + w + spare - aw;
                }
            }
            st.cats = cats;
        }
        self.clamp_targets();
        self.animate();
        self.grid.queue_draw();
    }

    pub fn set_logo(&self, key: &str, texture: gdk::Texture, light: bool) {
        self.logos.borrow_mut().insert(key.to_string(), (texture, light));
        if self.selected_key().as_deref() == Some(key) {
            self.update_head();
        }
        self.grid.queue_draw();
    }

    /// A decoded logo and its plate, for the search and the info sheet.
    pub fn logo(&self, key: &str) -> Option<(gdk::Texture, bool)> {
        self.logos.borrow().get(key).cloned()
    }

    pub fn has_logo(&self, key: &str) -> bool {
        self.logos.borrow().contains_key(key)
    }

    /// (channel key, programme start) of every reminder, for the bells.
    pub fn set_reminders(&self, r: HashSet<(String, i64)>) {
        *self.reminders.borrow_mut() = r;
        self.update_head();
        self.grid.queue_draw();
    }

    /// "Watching  TF1", "Connecting  TF1" or "No source answers  TF1".
    pub fn set_watching(&self, text: &str) {
        self.pip_label.set_text(text);
        self.pip_label.set_visible(!text.is_empty());
    }

    pub fn set_playing(&self, key: Option<&str>) {
        self.st.borrow_mut().playing = key.map(str::to_string);
        self.grid.queue_draw();
    }

    pub fn set_cats_focus(&self, on: bool) {
        self.st.borrow_mut().cats_focus = on;
        self.grid.queue_draw();
    }

    pub fn cats_focus(&self) -> bool {
        self.st.borrow().cats_focus
    }

    pub fn selected_key(&self) -> Option<String> {
        let st = self.st.borrow();
        st.rows.get(st.sel).map(|r| r.key.clone())
    }

    /// The channel and the programme picked.
    pub fn selected_prog(&self) -> Option<(String, Prog)> {
        let st = self.st.borrow();
        let i = Self::sel_prog_index(&st)?;
        let r = st.rows.get(st.sel)?;
        Some((r.key.clone(), r.progs[i].clone()))
    }

    pub fn tick(&self) {
        self.update_head();
        self.grid.queue_draw();
    }

    // ---- moving the selection -----------------------------------------

    fn sel_prog_index(st: &St) -> Option<usize> {
        let t = st.tc.max(st.w0);
        st.rows.get(st.sel)?.progs.iter().position(|p| p.start <= t && t < p.stop)
    }

    pub fn move_row(&self, d: i32) {
        {
            let mut st = self.st.borrow_mut();
            let n = st.rows.len() as i32;
            if n == 0 {
                return;
            }
            st.sel = (st.sel as i32 + d).clamp(0, n - 1) as usize;
        }
        self.after_move();
    }

    pub fn move_prog(&self, d: i32) -> bool {
        {
            let mut st = self.st.borrow_mut();
            let Some(row) = st.rows.get(st.sel) else { return false };
            let i = Self::sel_prog_index(&st);
            let t = st.tc.max(st.w0);
            let target = match (i, d > 0) {
                (Some(i), true) => row.progs.get(i + 1).filter(|p| p.start < st.w1).map(|p| p.start),
                (Some(i), false) => i.checked_sub(1).and_then(|j| row.progs.get(j)).filter(|p| p.stop > st.w0).map(|p| p.start.max(st.w0)),
                (None, true) => row.progs.iter().find(|p| p.start > t && p.start < st.w1).map(|p| p.start),
                (None, false) => row.progs.iter().rev().find(|p| p.stop <= t && p.stop > st.w0).map(|p| p.start.max(st.w0)),
            };
            match target {
                Some(t) => st.tc = t,
                None => return d > 0,
            }
        }
        self.after_move();
        true
    }

    pub fn home(&self) {
        {
            let mut st = self.st.borrow_mut();
            let now = store::now() as i64;
            st.tc = now;
            st.tx = ((now - st.w0) as f64 * self.per_s() - 4.0 * self.u).max(0.0);
        }
        self.clamp_targets();
        self.after_move();
    }

    fn after_move(&self) {
        self.ensure_visible();
        self.update_head();
        self.grid.queue_draw();
        self.animate();
    }

    fn ensure_visible(&self) {
        let (u, per_s) = (self.u, self.per_s());
        let (aw, ah) = (self.grid.width() as f64, self.grid.height() as f64);
        {
            let mut st = self.st.borrow_mut();
            let row = u * Theme::ROW;
            let page_h = ah - u * (Theme::TAB_BAR + Theme::HOURS);
            let y = st.sel as f64 * row;
            if y - row < st.ty {
                st.ty = y - row;
            } else if y + 2.0 * row > st.ty + page_h {
                st.ty = y + 2.0 * row - page_h;
            }
            if let Some(i) = Self::sel_prog_index(&st) {
                let p = &st.rows[st.sel].progs[i];
                let x0 = (p.start.max(st.w0) - st.w0) as f64 * per_s;
                let x1 = (p.stop.min(st.w1) - st.w0) as f64 * per_s;
                let page_w = aw - u * Theme::COLUMN;
                let (pad, grip) = (u, 3.0 * u);
                let (l, r) = (st.tx + pad, st.tx + page_w - pad);
                if x1 < l + grip {
                    st.tx = x0 - pad;
                } else if x0 > r - grip {
                    st.tx = (x1 - page_w + pad).min(x0 - pad);
                }
            }
        }
        self.clamp_targets();
    }

    fn clamp_targets(&self) {
        let u = self.u;
        let (aw, ah) = (self.grid.width() as f64, self.grid.height() as f64);
        let per_s = self.per_s();
        let mut st = self.st.borrow_mut();
        let max_x = ((st.w1 - st.w0) as f64 * per_s - (aw - u * Theme::COLUMN)).max(0.0);
        let max_y = (st.rows.len() as f64 * u * Theme::ROW + u * Theme::ROW * 0.5 - (ah - u * (Theme::TAB_BAR + Theme::HOURS))).max(0.0);
        let max_c = (st.tabs_w - aw).max(0.0);
        st.tx = st.tx.clamp(0.0, max_x);
        st.ty = st.ty.clamp(0.0, max_y);
        st.ctx = st.ctx.clamp(0.0, max_c);
    }

    fn animate(&self) {
        let animations = gtk::Settings::default().map(|s| s.is_gtk_enable_animations()).unwrap_or(true);
        if !animations {
            {
                let mut st = self.st.borrow_mut();
                st.sx = st.tx;
                st.sy = st.ty;
                st.cx = st.ctx;
            }
            self.grid.queue_draw();
            self.report_visible();
            return;
        }
        if self.animating.replace(true) {
            return;
        }
        self.st.borrow_mut().last_frame = 0;
        let this = self.this.borrow().clone();
        self.grid.add_tick_callback(move |g, clock| {
            let Some(me) = this.upgrade() else { return glib::ControlFlow::Break };
            let done = {
                let mut st = me.st.borrow_mut();
                let t = clock.frame_time();
                let dt = if st.last_frame == 0 { 1.0 / 60.0 } else { ((t - st.last_frame) as f64 / 1e6).clamp(0.001, 0.1) };
                st.last_frame = t;
                let k = 1.0 - (1.0 - Theme::EASE).powf(dt * 60.0);
                let (dx, dy, dc) = (st.tx - st.sx, st.ty - st.sy, st.ctx - st.cx);
                if dx.abs() < 0.5 && dy.abs() < 0.5 && dc.abs() < 0.5 {
                    st.sx = st.tx;
                    st.sy = st.ty;
                    st.cx = st.ctx;
                    true
                } else {
                    st.sx += dx * k;
                    st.sy += dy * k;
                    st.cx += dc * k;
                    false
                }
            };
            g.queue_draw();
            if done {
                me.animating.set(false);
                me.report_visible();
                glib::ControlFlow::Break
            } else {
                glib::ControlFlow::Continue
            }
        });
    }

    fn report_visible(&self) {
        let keys = {
            let st = self.st.borrow();
            let row = self.u * Theme::ROW;
            let first = (st.sy / row).floor().max(0.0) as usize;
            let last = ((st.sy + self.grid.height() as f64) / row).ceil() as usize + 1;
            st.rows.iter().skip(first).take(last.saturating_sub(first)).map(|r| r.key.clone()).collect::<Vec<_>>()
        };
        if let Some(f) = self.on_visible.borrow().as_ref() {
            f(keys);
        }
    }

    fn click(&self, x: f64, y: f64) {
        let u = self.u;
        let (left, top) = (self.left(), self.top());
        if y < top {
            let cat = {
                let st = self.st.borrow();
                let geom = self.tab_geom(&st.cats);
                geom.iter().position(|(tx, tw)| x + st.cx >= *tx && x + st.cx < tx + tw).and_then(|i| st.cats.get(i)).map(|(c, _)| c.clone())
            };
            if let (Some(c), Some(f)) = (cat, self.on_category.borrow().as_ref()) {
                f(c);
            }
            return;
        }
        let key = {
            let mut st = self.st.borrow_mut();
            let g0 = top + u * Theme::HOURS;
            if y < g0 {
                return;
            }
            let i = ((y - g0 + st.sy) / (u * Theme::ROW)) as usize;
            if i >= st.rows.len() {
                return;
            }
            st.sel = i;
            let col = left + u * Theme::COLUMN;
            if x > col {
                st.tc = st.w0 + ((x - col + st.sx) / self.per_s()) as i64;
            }
            st.cats_focus = false;
            st.rows[i].key.clone()
        };
        self.update_head();
        self.grid.queue_draw();
        if let Some(f) = self.on_play.borrow().as_ref() {
            f(key);
        }
    }

    // ---- the header -------------------------------------------------------

    /// The header for a show or an episode (None: back to the grid's).
    pub fn set_custom_head(&self, h: Option<Head>) {
        let Some(h) = h else {
            self.custom.set(false);
            self.head_pill.set_visible(false);
            self.head_pill2.set_visible(false);
            self.head_more.set_visible(false);
            self.update_head();
            return;
        };
        self.custom.set(true);
        self.clock.set_text(&hm(store::now() as i64));
        self.head_plate.set_visible(true);
        self.head_plate.remove_css_class("light");
        let inner = ((Theme::HEAD_LOGO - 0.6) * self.u).round() as i32;
        match &h.logo {
            Some(t) => {
                self.head_logo.set_content_fit(gtk::ContentFit::Cover);
                self.head_logo.set_size_request(inner * 16 / 9, inner);
                self.head_logo.set_paintable(Some(t));
                self.head_logo.set_visible(true);
                self.head_ini.set_visible(false);
            }
            None => {
                self.head_logo.set_visible(false);
                self.head_ini.set_text(&h.initials);
                self.head_ini.set_visible(true);
            }
        }
        self.head_ch.set_text(&h.line);
        self.head_title.set_text(&h.title);
        self.head_title.set_visible(!h.title.is_empty());
        self.head_time.set_text(&h.time);
        self.head_bar.set_visible(h.bar.is_some());
        if let Some(f) = h.bar {
            self.head_bar.set_fraction(f.clamp(0.0, 1.0));
        }
        self.head_remind.set_visible(false);
        self.head_remind_key.set_visible(false);
        self.head_desc.set_markup(&h.desc);
        self.head_desc.set_visible(!h.desc.is_empty());
        self.head_next.set_visible(false);
        self.head_action.set_text(&h.action);
        self.head_pill.set_visible(!h.action.is_empty());
        self.head_key.set_visible(h.action_key);
        self.head_action2.set_text(&h.action2);
        // the second pill has no pad button: it goes with its cap
        self.head_pill2.set_visible(!h.action2.is_empty() && crate::keys::mode() == crate::keys::Mode::Keyboard);
        self.head_more.set_visible(h.more);
    }

    fn update_head(&self) {
        if self.custom.get() {
            return;
        }
        let now = store::now() as i64;
        self.clock.set_text(&hm(now));
        self.head_logo.set_content_fit(gtk::ContentFit::Contain);
        self.head_desc.set_use_markup(false);
        let st = self.st.borrow();
        let Some(row) = st.rows.get(st.sel) else {
            self.head_remind_key.set_visible(false);
            for l in [&self.head_ch, &self.head_title, &self.head_time, &self.head_desc, &self.head_next, &self.head_remind] {
                l.set_text("");
            }
            self.head_bar.set_visible(false);
            self.head_plate.set_visible(false);
            return;
        };
        self.head_plate.set_visible(true);
        match self.logos.borrow().get(&row.key) {
            Some((t, light)) => {
                // shown at the size it was decoded to: never enlarged
                let scale = self.grid.scale_factor().max(1);
                self.head_logo.set_size_request(t.width() / scale, t.height() / scale);
                self.head_logo.set_paintable(Some(t));
                self.head_logo.set_visible(true);
                self.head_ini.set_visible(false);
                if *light {
                    self.head_plate.add_css_class("light");
                } else {
                    self.head_plate.remove_css_class("light");
                }
            }
            None => {
                self.head_logo.set_visible(false);
                self.head_ini.set_text(&crate::catalog::initials(&row.name));
                self.head_ini.set_visible(true);
                self.head_plate.remove_css_class("light");
            }
        }
        self.head_ch.set_text(&format!("{}   {}", row.number, row.name));
        let i = Self::sel_prog_index(&st);
        self.head_remind.set_text("");
        let mut remind_key: Option<&str> = None;
        match i.map(|i| &row.progs[i]) {
            Some(p) => {
                self.head_title.set_text(&p.title);
                let cat = p.category.as_deref().map(|c| format!("   ·   {c}")).unwrap_or_default();
                self.head_time.set_text(&format!("{} – {}{}", hm(p.start), hm(p.stop), cat));
                let live = p.start <= now && now < p.stop;
                self.head_bar.set_visible(live);
                if live {
                    self.head_bar.set_fraction((now - p.start) as f64 / (p.stop - p.start).max(1) as f64);
                }
                if p.start > now {
                    let set = self.reminders.borrow().contains(&(row.key.clone(), p.start));
                    self.head_remind.set_text(if set { "Reminder set" } else { "" });
                    remind_key = Some(if set { "Remove" } else { "Remind me" });
                }
                self.head_desc.set_text(p.desc.as_deref().unwrap_or(""));
            }
            None => {
                // no guide: nothing said, the channel line alone
                self.head_title.set_text("");
                self.head_time.set_text("");
                self.head_bar.set_visible(false);
                self.head_desc.set_text("");
            }
        }
        self.head_remind.set_visible(!self.head_remind.text().is_empty());
        if let Some(l) = self.head_remind_key.last_child().and_then(|w| w.downcast::<gtk::Label>().ok()) {
            l.set_text(remind_key.unwrap_or(""));
        }
        self.head_remind_key.set_visible(remind_key.is_some());
        self.head_title.set_visible(!self.head_title.text().is_empty());
        let from = i.map(|i| i + 1).unwrap_or_else(|| row.progs.iter().position(|p| p.start > st.tc).unwrap_or(row.progs.len()));
        let next: Vec<String> = row.progs.iter().skip(from).take(2).map(|p| format!("{}  {}", hm(p.start), p.title)).collect();
        self.head_next.set_text(&next.join("      "));
        self.head_desc.set_visible(!self.head_desc.text().is_empty());
        self.head_next.set_visible(!next.is_empty());
    }

    // ---- painting ---------------------------------------------------------

    fn layout(&self, text: &str, width: f64, font: u8) -> pango::Layout {
        let w = width.max(1.0).round() as i32;
        let key = (text.to_string(), w, font);
        if let Some(l) = self.layouts.borrow().get(&key) {
            return l.clone();
        }
        let l = pango::Layout::new(&self.grid.pango_context());
        l.set_font_description(Some(&self.fonts[font as usize]));
        l.set_text(text);
        l.set_width(w * pango::SCALE);
        l.set_ellipsize(pango::EllipsizeMode::End);
        l.set_single_paragraph_mode(true);
        if font == F_LABEL {
            let attrs = pango::AttrList::new();
            attrs.insert(pango::AttrInt::new_letter_spacing((0.08 * self.u * pango::SCALE as f64) as i32));
            l.set_attributes(Some(&attrs));
        }
        let mut cache = self.layouts.borrow_mut();
        if cache.len() > 4000 {
            cache.clear();
        }
        cache.insert(key, l.clone());
        l
    }

    fn text(&self, s: &gtk::Snapshot, t: &str, x: f64, y: f64, width: f64, font: u8, color: gdk::RGBA) -> f64 {
        let l = self.layout(t, width, font);
        s.save();
        s.translate(&graphene::Point::new(x as f32, y as f32));
        s.append_layout(&l, &color);
        s.restore();
        l.pixel_size().0 as f64
    }

    fn rounded_fill(s: &gtk::Snapshot, r: graphene::Rect, radius: f32, color: &gdk::RGBA) {
        s.push_rounded_clip(&gsk::RoundedRect::from_rect(r, radius));
        s.append_color(color, &r);
        s.pop();
    }

    /// A small bell, `sz` tall, its top left at (x, y).
    fn bell(s: &gtk::Snapshot, x: f64, y: f64, sz: f64, color: &gdk::RGBA) {
        let p = |a: f64, b: f64| ((x + a * sz) as f32, (y + b * sz) as f32);
        let b = gsk::PathBuilder::new();
        let (mx, my) = p(0.5, 0.06);
        b.move_to(mx, my);
        let (c1x, c1y) = p(0.8, 0.06);
        let (c2x, c2y) = p(0.86, 0.3);
        let (ex, ey) = p(0.86, 0.5);
        b.cubic_to(c1x, c1y, c2x, c2y, ex, ey);
        let (lx, ly) = p(0.86, 0.66);
        b.line_to(lx, ly);
        let (lx, ly) = p(0.98, 0.8);
        b.line_to(lx, ly);
        let (lx, ly) = p(0.02, 0.8);
        b.line_to(lx, ly);
        let (lx, ly) = p(0.14, 0.66);
        b.line_to(lx, ly);
        let (lx, ly) = p(0.14, 0.5);
        b.line_to(lx, ly);
        let (c1x, c1y) = p(0.14, 0.3);
        let (c2x, c2y) = p(0.2, 0.06);
        b.cubic_to(c1x, c1y, c2x, c2y, mx, my);
        b.close();
        let (cx, cy) = p(0.5, 0.9);
        b.add_circle(&graphene::Point::new(cx, cy), (0.1 * sz) as f32);
        s.append_fill(&b.to_path(), gsk::FillRule::Winding, color);
    }

    /// The picked tab and its two concave corners, in the panel's colour,
    /// so tab and panel read as one shape: the tab rises from the panel's
    /// top edge at `top`.
    fn tab_shape(s: &gtk::Snapshot, x: f64, tw: f64, y0: f64, top: f64, r: f64, color: &gdk::RGBA) {
        let b = gsk::PathBuilder::new();
        b.add_rounded_rect(&gsk::RoundedRect::new(rect(x, y0, tw, top - y0 + 1.0), size(r), size(r), size(0.0), size(0.0)));
        let k = std::f32::consts::FRAC_1_SQRT_2;
        let (x, tw, top, r) = (x as f32, tw as f32, top as f32, r as f32);
        // bottom left: the square between tab and panel, minus a quarter circle
        b.move_to(x - r, top + 1.0);
        b.line_to(x, top + 1.0);
        b.line_to(x, top - r);
        b.conic_to(x, top, x - r, top, k);
        b.close();
        // bottom right
        b.move_to(x + tw + r, top + 1.0);
        b.line_to(x + tw, top + 1.0);
        b.line_to(x + tw, top - r);
        b.conic_to(x + tw, top, x + tw + r, top, k);
        b.close();
        s.append_fill(&b.to_path(), gsk::FillRule::Winding, color);
    }

    /// The column: section names, entries with their summary, and the
    /// entry picked drawn in the panel's colour up to the column's right
    /// edge, where the page's panel begins, with a concave corner above
    /// and below so entry and panel read as one shape.
    fn paint_nav(&self, s: &gtk::Snapshot, w: f64, _h: f64) {
        let u = self.u;
        let nav = self.navst.borrow();
        let geom = self.nav_geom();
        let e = u * Theme::ENTRY;
        let r = Theme::TAB_R * u;
        let panel_c = rgba(Theme::PANEL, 1.0);
        let tx = 1.1 * u;
        let tw = w - tx - Theme::NAV_GAP * u - 0.4 * u;
        for (i, p) in Page::ALL.iter().enumerate() {
            let y = geom[i];
            if let Some(name) = p.section() {
                let (_, lh) = self.layout(name, tw, F_LABEL).pixel_size();
                let base = y;
                self.text(s, name, tx, base - 0.5 * u - lh as f64, tw, F_LABEL, rgba(Theme::TEXT_DIM, 1.0));
            }
            let on = i == nav.sel;
            // every entry but Search sits under a section's name
            let ind = if i > 0 { Theme::INDENT * u } else { 0.0 };
            if on {
                let b = gsk::PathBuilder::new();
                b.add_rounded_rect(&gsk::RoundedRect::new(rect(ind, y, w + 1.0 - ind, e), size(r), size(0.0), size(0.0), size(r)));
                let k = std::f32::consts::FRAC_1_SQRT_2;
                let (wf, yt, yb, rf) = (w as f32, y as f32, (y + e) as f32, r as f32);
                // above: on the panel's top edge, the corner it makes with
                // the page's first tab, flush with that edge
                b.move_to(wf - rf, yt);
                b.line_to(wf + 1.0, yt);
                b.line_to(wf + 1.0, yt - rf);
                b.line_to(wf, yt - rf);
                b.conic_to(wf, yt, wf - rf, yt, k);
                b.close();
                b.move_to(wf - rf, yb);
                b.line_to(wf + 1.0, yb);
                b.line_to(wf + 1.0, yb + rf);
                b.line_to(wf, yb + rf);
                b.conic_to(wf, yb, wf - rf, yb, k);
                b.close();
                s.append_fill(&b.to_path(), gsk::FillRule::Winding, &panel_c);
                // the menu has the keyboard: the entry carries the contour,
                // as the selection does everywhere else
                if nav.focus {
                    let rr = gsk::RoundedRect::from_rect(rect(ind + 0.3 * u, y + 0.2 * u, w - ind - 0.9 * u, e - 0.4 * u), (0.6 * u) as f32);
                    s.append_border(&rr, &[1.5; 4], &[rgba(Theme::INK, Theme::CONTOUR); 4]);
                }
            } else if nav.hover == Some(i) {
                Self::rounded_fill(s, rect(ind, y + 0.1 * u, w - ind - Theme::NAV_GAP * u, e - 0.2 * u), (0.6 * u) as f32, &rgba(Theme::INK, Theme::HOVER));
            }
            let (ex, ew) = (tx + ind, tw - ind);
            let (_, th) = self.layout(p.title(), ew, F_NAME).pixel_size();
            let sum = nav.summaries.get(i).map(String::as_str).unwrap_or("");
            let (_, sh) = self.layout(if sum.is_empty() { " " } else { sum }, ew, F_SMALL).pixel_size();
            let block = th as f64 + if sum.is_empty() { 0.0 } else { sh as f64 + 0.05 * u };
            let ty = y + (e - block) / 2.0;
            let (title_c, sum_c) = if on { (rgba(Theme::INK, 1.0), rgba(Theme::TEXT_DIM, 1.0)) } else { (rgba(Theme::TEXT_DIM, 1.0), rgba(Theme::TEXT_FAINT, 1.0)) };
            self.text(s, p.title(), ex, ty, ew, F_NAME, title_c);
            if !sum.is_empty() {
                self.text(s, sum, ex, ty + th as f64 + 0.05 * u, ew, F_SMALL, sum_c);
            }
        }
    }

    fn paint(&self, s: &gtk::Snapshot, w: f64, h: f64) {
        let started = self.debug.then(std::time::Instant::now);
        let u = self.u;
        let per_s = self.per_s();
        let left = self.left();
        let (row, col, hours) = (u * Theme::ROW, left + u * Theme::COLUMN, u * Theme::HOURS);
        let top = self.top();
        // where the rows begin: under the tabs and the hour row
        let g0 = top + hours;
        let st = self.st.borrow();
        let now = store::now() as i64;
        let first = (st.sy / row).floor().max(0.0) as usize;
        let last = (((st.sy + h - g0) / row).ceil() as usize + 1).min(st.rows.len());
        let x_of = |t: i64| col + (t - st.w0) as f64 * per_s - st.sx;
        let t_left = st.w0 + (st.sx / per_s) as i64;
        let t_right = st.w0 + ((st.sx + w - col) / per_s) as i64 + 1;
        let sel_t = st.tc.max(st.w0);
        let pad = 0.55 * u;
        let radius = Theme::RADIUS * u as f32;
        let text_h = Theme::TEXT * u * 1.25;
        let panel_c = rgba(Theme::PANEL, 1.0);
        let pr = Theme::TAB_R * u;

        s.append_color(&rgba(Theme::BG, 1.0), &rect(0.0, 0.0, w, h));

        // ---- the tabs, the picked one running down into the panel
        s.push_clip(&rect(0.0, 0.0, w, top));
        let geom = self.tab_geom(&st.cats);
        let y0 = 0.35 * u;
        for (i, ((name, n), (tx0, tw))) in st.cats.iter().zip(geom.iter()).enumerate() {
            let x = tx0 - st.cx;
            if x + tw < -pr || x > w + pr {
                continue;
            }
            let on = i == st.cat;
            if on {
                Self::tab_shape(s, x, *tw, y0, top, pr, &panel_c);
                if st.cats_focus {
                    Self::rounded_fill(s, rect(x + pr, y0 + 0.2 * u, tw - 2.0 * pr, 0.2 * u), (0.1 * u) as f32, &rgba(Theme::INK, 1.0));
                }
            }
            let label = Self::tab_label(name);
            let (nw, th) = self.layout(&label, 30.0 * u, F_TAB).pixel_size();
            let ty = y0 + (top - y0 - th as f64) / 2.0;
            let name_c = if on { rgba(Theme::INK, 1.0) } else { rgba(Theme::TEXT_DIM, 1.0) };
            self.text(s, &label, x + Theme::TAB_PAD * u, ty, 30.0 * u, F_TAB, name_c);
            self.text(s, &n.to_string(), x + Theme::TAB_PAD * u + nw as f64 + 0.55 * u, ty + 0.1 * u, 4.0 * u, F_SMALL, rgba(Theme::TEXT_FAINT, 1.0));
        }
        // tabs scrolled past an edge fade out rather than being cut
        let fade = 2.0 * u;
        let bg = rgba(Theme::BG, 1.0);
        let clear = rgba(Theme::BG, 0.0);
        if st.cx > 0.5 {
            s.append_linear_gradient(&rect(0.0, 0.0, fade, top - 0.1 * u), &graphene::Point::new(0.0, 0.0), &graphene::Point::new(fade as f32, 0.0),
                &[gsk::ColorStop::new(0.0, bg), gsk::ColorStop::new(1.0, clear)]);
        }
        if st.tabs_w - st.cx > w + 0.5 {
            s.append_linear_gradient(&rect(w - fade, 0.0, fade, top - 0.1 * u), &graphene::Point::new((w - fade) as f32, 0.0), &graphene::Point::new(w as f32, 0.0),
                &[gsk::ColorStop::new(0.0, clear), gsk::ColorStop::new(1.0, bg)]);
        }
        s.pop();

        // ---- the panel; everything below is clipped to its rounded corner
        // square top-left corner when the first tab sits right on it
        let tl = if st.cat == 0 && st.cx < 1.0 { 0.0 } else { pr };
        let panel = gsk::RoundedRect::new(rect(left, top, w - left, h - top), size(tl), size(pr), size(0.0), size(0.0));
        s.push_rounded_clip(&panel);
        s.append_color(&panel_c, &rect(left, top, w - left, h - top));

        // programmes, in three passes: the cells, then the past hatched
        // and veiled over them, then every title on top, so the hatching
        // marks the time without dimming what is on now
        s.push_clip(&rect(col, g0, w - col, h - g0));
        let nx = x_of(now);
        let reminders = self.reminders.borrow();
        let mut sel_right: Option<f64> = None;
        let nav_focus = self.navst.borrow().focus;
        let picked_focus = !st.cats_focus && !nav_focus;
        struct Label {
            x: f64,
            y: f64,
            clip: graphene::Rect,
            bell: bool,
            time: Option<String>,
            title: String,
            width_end: f64,
            title_c: gdk::RGBA,
            time_c: gdk::RGBA,
            font: u8,
        }
        let mut labels: Vec<Label> = Vec::new();
        for i in first..last {
            let r = &st.rows[i];
            let y = g0 + i as f64 * row - st.sy;
            let selrow = i == st.sel;
            let (cy, ch) = (y + 0.22 * u, row - 0.44 * u);
            let ty = cy + (ch - text_h) / 2.0;
            if r.progs.is_empty() {
                let rr = rect(col + 2.0, cy, w - col - 4.0, ch);
                Self::rounded_fill(s, rr, radius, &mix(Theme::CELL_EMPTY));
                if selrow {
                    sel_right = Some(w - 2.0);
                }
                s.append_color(&rgba(Theme::INK, Theme::RULE), &rect(col, y, w - col, 1.0));
                continue;
            }
            for p in r.progs.iter().filter(|p| p.stop > t_left.max(st.w0) && p.start < t_right.min(st.w1)) {
                let (a, b) = (p.start.max(st.w0), p.stop.min(st.w1));
                let (x, cw) = (x_of(a) + 2.0, (b - a) as f64 * per_s - 4.0);
                if cw <= 1.0 {
                    continue;
                }
                let live = p.start <= now && now < p.stop;
                let over = p.stop <= now;
                let sel = selrow && p.start <= sel_t && sel_t < p.stop;
                if sel {
                    sel_right = Some((x + cw).min(w - 2.0));
                }
                let rr = rect(x, cy, cw, ch);
                let k = if sel && picked_focus { Theme::CELL_PICKED } else if live { Theme::CELL_LIVE } else { Theme::CELL };
                Self::rounded_fill(s, rr, radius, &mix(k));
                let tx = (x + pad).max(col + pad);
                let avail = x + cw - pad - tx;
                if avail > 0.8 * u {
                    let bright = live || sel;
                    let title_c = if bright {
                        rgba(Theme::INK, 1.0)
                    } else if over {
                        rgba(Theme::TEXT_FAINT, 1.0)
                    } else {
                        rgba(Theme::TEXT_DIM, 1.0)
                    };
                    labels.push(Label {
                        x: tx,
                        y: ty,
                        clip: rr,
                        bell: reminders.contains(&(r.key.clone(), p.start)),
                        time: (avail > 6.0 * u).then(|| hm(p.start)),
                        title: p.title.clone(),
                        width_end: x + cw - pad,
                        title_c,
                        time_c: rgba(Theme::TEXT_FAINT, 1.0),
                        font: if bright { F_TEXT_BOLD } else { F_TEXT },
                    });
                }
            }
            s.append_color(&rgba(Theme::INK, Theme::RULE), &rect(col, y, w - col, 1.0));
        }
        drop(reminders);
        // the past: a veil and diagonal hatching, anchored to the grid so
        // they scroll with it
        if nx > col {
            let past = rect(col, g0, nx.min(w) - col, h - g0);
            s.append_color(&rgba(Theme::PANEL, Theme::PAST_VEIL), &past);
            let step = Theme::HATCH_STEP * u;
            let (ox, oy) = ((col - st.sx) as f32, (g0 - st.sy) as f32);
            s.append_repeating_linear_gradient(
                &past,
                &graphene::Point::new(ox, oy),
                &graphene::Point::new(ox + step as f32, oy + step as f32),
                &[
                    gsk::ColorStop::new(0.0, rgba(Theme::INK, Theme::HATCH)),
                    gsk::ColorStop::new(0.3, rgba(Theme::INK, Theme::HATCH)),
                    gsk::ColorStop::new(0.3, rgba(Theme::INK, 0.0)),
                    gsk::ColorStop::new(1.0, rgba(Theme::INK, 0.0)),
                ],
            );
            if nx <= w {
                s.append_color(&rgba(Theme::INK, 0.35), &rect(nx - 0.5, g0, 1.0, h - g0));
            }
        }
        for l in &labels {
            s.push_clip(&l.clip);
            let mut x = l.x;
            if l.bell {
                Self::bell(s, x, l.y + 0.12 * u, 0.78 * u, &l.title_c);
                x += 1.15 * u;
            }
            if let Some(t) = &l.time {
                let tw = self.text(s, t, x, l.y + 0.08 * u, 3.0 * u, F_SMALL, l.time_c);
                x += tw + 0.5 * u;
            }
            self.text(s, &l.title, x, l.y, l.width_end - x, l.font, l.title_c);
            s.pop();
        }
        s.pop();

        // the channel column, over the programmes
        s.append_color(&panel_c, &rect(left, g0, col - left, h - g0));
        s.push_clip(&rect(left, g0, col - left, h - g0));
        let logos = self.logos.borrow();
        let ls = Theme::LOGO * u;
        for i in first..last {
            let r = &st.rows[i];
            let y = g0 + i as f64 * row - st.sy;
            let selrow = i == st.sel;
            self.text(s, &r.number.to_string(), left + 0.6 * u, y + (row - Theme::SMALL * u * 1.25) / 2.0, 1.6 * u, F_SMALL, rgba(Theme::TEXT_FAINT, 1.0));
            let (lx, ly) = (left + 2.3 * u, y + (row - ls) / 2.0);
            let logo = logos.get(&r.key);
            let plate_c = match logo {
                Some((_, true)) => rgba(Theme::LIGHT_PLATE, 1.0),
                _ => rgba(Theme::INK, 0.07),
            };
            Self::rounded_fill(s, rect(lx, ly, ls, ls), 0.45 * u as f32, &plate_c);
            match logo {
                Some((t, _)) => {
                    let box_s = ls - 0.44 * u;
                    let k = (box_s / t.width() as f64).min(box_s / t.height() as f64);
                    let (tw, th) = (t.width() as f64 * k, t.height() as f64 * k);
                    // mipmapped: a wide logo shrunk this far stays crisp
                    s.append_scaled_texture(t, gsk::ScalingFilter::Trilinear, &rect(lx + (ls - tw) / 2.0, ly + (ls - th) / 2.0, tw, th));
                }
                None => {
                    let ini = crate::catalog::initials(&r.name);
                    let (iw, ih) = self.layout(&ini, ls, F_INI).pixel_size();
                    self.text(s, &ini, lx + (ls - iw as f64) / 2.0, ly + (ls - ih as f64) / 2.0, ls, F_INI, rgba(Theme::TEXT_DIM, 1.0));
                }
            }
            let playing = st.playing.as_deref() == Some(r.key.as_str());
            let name_x = lx + ls + 0.6 * u;
            let name_w = col - name_x - if playing { 1.3 * u } else { 0.4 * u };
            let name_c = if selrow { rgba(Theme::INK, 1.0) } else { rgba(Theme::TEXT_DIM, 1.0) };
            self.text(s, &r.name, name_x, y + (row - 0.86 * u * 1.25) / 2.0, name_w, F_NAME, name_c);
            if playing {
                let d = 0.42 * u;
                Self::rounded_fill(s, rect(col - 0.95 * u, y + (row - d) / 2.0, d, d), d as f32 / 2.0, &rgba(Theme::INK, 1.0));
            }
        }
        drop(logos);
        s.pop();

        // one contour from the channel to the programme picked
        if st.sel >= first && st.sel < last {
            let y = g0 + st.sel as f64 * row - st.sy;
            let x1 = sel_right.unwrap_or(col - 0.2 * u).max(col - 0.2 * u);
            let x0 = left + 0.2 * u;
            let rr = gsk::RoundedRect::from_rect(rect(x0, y + 0.1 * u, x1 + 0.12 * u - x0, row - 0.2 * u), (0.62 * u) as f32);
            let a = if picked_focus { Theme::CONTOUR } else { 0.3 };
            s.push_clip(&rect(left, g0, w - left, h - g0));
            s.append_border(&rr, &[1.5; 4], &[rgba(Theme::INK, a); 4]);
            s.pop();
        }

        // the hour row, last
        s.append_color(&panel_c, &rect(left, top, w - left, hours));
        s.push_clip(&rect(col, top, w - col, hours));
        let mut t = st.w0;
        while t < st.w1 {
            let x = x_of(t);
            if x > col - 4.0 * u && x < w {
                s.append_color(&rgba(Theme::INK, 0.14), &rect(x, top + 0.25 * u, 1.0, hours - 0.5 * u));
                self.text(s, &hm(t), x + 0.35 * u, top + (hours - Theme::SMALL * u * 1.25) / 2.0, 4.0 * u, F_SMALL, rgba(Theme::TEXT_FAINT, 1.0));
            }
            t += 1800;
        }
        // past hours fade like the past programmes
        if nx > col {
            s.append_color(&rgba(Theme::PANEL, Theme::PAST_VEIL), &rect(col, top, nx.min(w) - col, hours));
        }
        // the time itself, on a pill where the hatching ends
        if nx >= col && nx <= w {
            let label = hm(now);
            let (tw, th) = self.layout(&label, 4.0 * u, F_SMALL).pixel_size();
            let (pw, ph) = (tw as f64 + 0.9 * u, (th as f64 + 0.3 * u).min(hours - 0.2 * u));
            let px = (nx - pw / 2.0).clamp(col, w - pw);
            let pill = rect(px, top + (hours - ph) / 2.0, pw, ph);
            Self::rounded_fill(s, pill, (ph / 2.0) as f32, &rgba(Theme::INK, 1.0));
            self.text(s, &label, px + 0.45 * u, top + (hours - th as f64) / 2.0, tw as f64 + 1.0, F_SMALL, rgba(Theme::BG, 1.0));
        }
        s.pop();
        s.pop(); // panel
        drop(st);

        if let Some(t0) = started {
            let ms = t0.elapsed().as_secs_f64() * 1000.0;
            if ms > 8.0 {
                eprintln!("antenne: guide frame described in {ms:.1} ms ({} layouts cached)", self.layouts.borrow().len());
            }
        }
    }
}
