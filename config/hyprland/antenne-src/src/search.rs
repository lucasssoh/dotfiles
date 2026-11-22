//! Search, a page of the guide's column: the field in a tab over the
//! panel, and under it a plain list of what matches. Yours first (by name,
//! number, category, or a programme still to come), then "Elsewhere":
//! every channel iptv-org lists in countries not turned on. ↑ ↓ move the
//! selection, kept in view with a row to spare; Enter plays.

use gtk4 as gtk;
use gtk::prelude::*;
use gtk::{gdk, glib, pango};
use std::cell::{Cell, RefCell};
use std::rc::Rc;

pub struct Hit {
    pub key: String,
    /// The channel number, or the country code for one from elsewhere.
    pub tag: String,
    pub name: String,
    pub sub: String,
    /// The group it is listed under ("CHANNELS", "PROGRAMMES"…); a new
    /// name opens a new group.
    pub group: &'static str,
    /// No source answered at the last check: shown, greyed.
    pub dead: bool,
    /// How far the programme on now has gone, for its bar.
    pub progress: Option<f64>,
    pub logo: Option<(gdk::Texture, bool)>,
    /// A sign in the plate instead of a logo ("▶", "+") for a pasted link.
    pub glyph: Option<&'static str>,
}

pub struct SearchView {
    pub root: gtk::Box,
    pub entry: gtk::Entry,
    list: gtk::Box,
    scroller: gtk::ScrolledWindow,
    rows: RefCell<Vec<gtk::Box>>,
    keys: RefCell<Vec<String>>,
    sel: Cell<usize>,
    /// The plates' inside height, in pixels.
    logo_h: f64,
    pub on_change: RefCell<Option<Box<dyn Fn(String)>>>,
    pub on_pick: RefCell<Option<Box<dyn Fn(String)>>>,
}

/// `max_h`: the plate's inside, in pixels.
fn plate(logo: &Option<(gdk::Texture, bool)>, name: &str, glyph: Option<&str>, max_h: f64, scale: i32) -> gtk::Box {
    let p = gtk::Box::new(gtk::Orientation::Vertical, 0);
    p.add_css_class("splate");
    p.set_valign(gtk::Align::Center);
    p.set_overflow(gtk::Overflow::Hidden);
    match logo {
        Some((t, light)) => {
            if *light {
                p.add_css_class("light");
            }
            p.append(&crate::guide::logo_picture(t, max_h, scale));
        }
        None => {
            let l = gtk::Label::new(Some(&glyph.map(str::to_string).unwrap_or_else(|| crate::catalog::initials(name))));
            l.add_css_class("sini");
            l.set_vexpand(true);
            p.append(&l);
        }
    }
    p
}

fn group(text: &str) -> gtk::Label {
    let l = gtk::Label::new(Some(text));
    l.add_css_class("sgroup");
    l.set_xalign(0.0);
    l
}

impl SearchView {
    pub fn new(u: f64) -> Rc<Self> {
        let root = gtk::Box::new(gtk::Orientation::Vertical, 0);
        root.add_css_class("spage");
        // the tab: the field, on the panel's top edge, a concave corner after it
        let tabs = gtk::Box::new(gtk::Orientation::Horizontal, 0);
        tabs.add_css_class("ptabs");
        let tab = gtk::Box::new(gtk::Orientation::Horizontal, 0);
        tab.add_css_class("stab");
        let icon = gtk::Image::from_icon_name("system-search-symbolic");
        icon.add_css_class("sicon");
        let entry = gtk::Entry::new();
        entry.add_css_class("sfield");
        entry.set_placeholder_text(Some("Search channels and programmes"));
        entry.set_width_chars(26);
        entry.set_valign(gtk::Align::Center);
        tab.append(&icon);
        tab.append(&entry);
        let foot = gtk::Box::new(gtk::Orientation::Horizontal, 0);
        foot.add_css_class("tfoot");
        foot.set_valign(gtk::Align::End);
        tabs.append(&tab);
        tabs.append(&foot);
        let panel = gtk::Box::new(gtk::Orientation::Vertical, 0);
        panel.add_css_class("spanel");
        panel.set_vexpand(true);
        let list = gtk::Box::new(gtk::Orientation::Vertical, 0);
        list.add_css_class("slist");
        list.set_halign(gtk::Align::Start);
        let scroller = gtk::ScrolledWindow::builder()
            .hscrollbar_policy(gtk::PolicyType::Never)
            .vscrollbar_policy(gtk::PolicyType::External)
            .vexpand(true)
            .child(&list)
            .build();
        panel.append(&scroller);
        root.append(&tabs);
        root.append(&panel);
        let me = Rc::new(SearchView {
            root,
            entry: entry.clone(),
            list,
            scroller,
            rows: RefCell::new(vec![]),
            keys: RefCell::new(vec![]),
            sel: Cell::new(0),
            logo_h: 1.6 * u,
            on_change: RefCell::new(None),
            on_pick: RefCell::new(None),
        });
        let w = Rc::downgrade(&me);
        entry.connect_changed(move |e| {
            if let Some(me) = w.upgrade() {
                if let Some(f) = me.on_change.borrow().as_ref() {
                    f(e.text().to_string());
                }
            }
        });
        me
    }

    pub fn query(&self) -> String {
        self.entry.text().trim().to_string()
    }

    /// The keyboard to the field, the cursor at the end.
    pub fn focus(&self) {
        self.entry.grab_focus_without_selecting();
        self.entry.set_position(-1);
    }

    /// Each hit under its group's name, in the order given.
    pub fn set_hits(self: &Rc<Self>, hits: Vec<Hit>, empty_text: Option<String>) {
        while let Some(c) = self.list.first_child() {
            self.list.remove(&c);
        }
        let mut rows = vec![];
        let mut keys = vec![];
        let mut current = "";
        for (i, h) in hits.into_iter().enumerate() {
            if h.group != current {
                current = h.group;
                self.list.append(&group(current));
            }
            let row = gtk::Box::new(gtk::Orientation::Horizontal, 0);
            row.add_css_class("srow");
            if h.dead {
                row.add_css_class("dead");
            }
            let text = gtk::Box::new(gtk::Orientation::Vertical, 0);
            text.set_valign(gtk::Align::Center);
            text.set_hexpand(true);
            let name = gtk::Label::new(Some(&h.name));
            name.add_css_class("sname");
            name.set_xalign(0.0);
            name.set_ellipsize(pango::EllipsizeMode::End);
            let sub = gtk::Label::new(Some(&h.sub));
            sub.add_css_class("ssub");
            sub.set_xalign(0.0);
            sub.set_ellipsize(pango::EllipsizeMode::End);
            text.append(&name);
            text.append(&sub);
            if let Some(f) = h.progress {
                let bar = gtk::ProgressBar::new();
                bar.add_css_class("sbar");
                bar.set_halign(gtk::Align::Start);
                bar.set_fraction(f.clamp(0.0, 1.0));
                text.append(&bar);
            }
            let tag = gtk::Label::new(Some(&h.tag));
            tag.add_css_class("snum");
            tag.set_valign(gtk::Align::Center);
            tag.set_xalign(1.0);
            row.append(&plate(&h.logo, &h.name, h.glyph, self.logo_h, self.list.scale_factor()));
            row.append(&text);
            row.append(&tag);
            let click = gtk::GestureClick::new();
            let w = Rc::downgrade(self);
            click.connect_released(move |_, _, _, _| {
                if let Some(me) = w.upgrade() {
                    me.select(i);
                    me.pick();
                }
            });
            row.add_controller(click);
            self.list.append(&row);
            rows.push(row);
            keys.push(h.key);
        }
        if rows.is_empty() {
            if let Some(t) = empty_text {
                let l = gtk::Label::new(Some(&t));
                l.add_css_class("sempty");
                l.set_xalign(0.0);
                self.list.append(&l);
            }
        }
        *self.rows.borrow_mut() = rows;
        *self.keys.borrow_mut() = keys;
        self.sel.set(usize::MAX);
        self.scroller.vadjustment().set_value(0.0);
        self.select(0);
    }

    pub fn move_sel(&self, d: i32) {
        let n = self.rows.borrow().len() as i32;
        if n == 0 {
            return;
        }
        let cur = if self.sel.get() == usize::MAX { 0 } else { self.sel.get() as i32 };
        self.select((cur + d).clamp(0, n - 1) as usize);
    }

    fn select(&self, i: usize) {
        let rows = self.rows.borrow();
        if rows.is_empty() {
            return;
        }
        let i = i.min(rows.len() - 1);
        if let Some(r) = rows.get(self.sel.get()) {
            r.remove_css_class("sel");
        }
        self.sel.set(i);
        let row = rows[i].clone();
        row.add_css_class("sel");
        drop(rows);
        // in view with a row to spare, once laid out
        let sc = self.scroller.clone();
        let list = self.list.clone();
        self.list.add_tick_callback(move |_, _| {
            if let Some(r) = row.compute_bounds(&list) {
                let adj = sc.vadjustment();
                let (y, h) = (r.y() as f64, r.height() as f64);
                let v = adj.value();
                if y - h < v {
                    adj.set_value((y - h).max(0.0));
                } else if y + 2.0 * h > v + adj.page_size() {
                    adj.set_value((y + 2.0 * h - adj.page_size()).min(adj.upper() - adj.page_size()));
                }
            }
            glib::ControlFlow::Break
        });
    }

    pub fn pick(&self) {
        let key = self.keys.borrow().get(self.sel.get()).cloned();
        if let (Some(k), Some(f)) = (key, self.on_pick.borrow().as_ref()) {
            f(k);
        }
    }
}
