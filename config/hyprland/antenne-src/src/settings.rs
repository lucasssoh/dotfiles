//! The settings pages of the guide's column: Countries, My sources,
//! Checks, Listings, Playback. One panel, a title and a line on what the
//! page is for, then lines separated by a hairline: no blocks. Keys are
//! GTK's own (Tab and the arrows move, Space and Enter act); Esc gives the
//! keyboard back to the column.

use crate::catalog::{host_of, link_kind, LinkKind};
use crate::guide::Page;
use gtk4 as gtk;
use gtk::prelude::*;
use gtk::pango;
use std::cell::RefCell;
use std::rc::Rc;

pub enum Action {
    AddCountry(String),
    RemoveCountry(String),
    AddList(String),
    RemoveList(String),
    /// (name, link): a stream, a page or a video, as a channel.
    AddSource(String, String),
    RemoveSource(String),
    ChooseFile,
    OpenFolder,
    /// Draw the page again (the name step opened or closed).
    Redraw,
    Every(u64),
    CheckNow,
    OpenLast(bool),
    Logos(bool),
    LowerOnWeak(bool),
    AutoNext(bool),
}

pub struct CountryRow {
    pub cc: String,
    pub name: String,
    pub detail: String,
}

pub struct ListRow {
    pub spec: String,
    pub name: String,
    pub detail: String,
    pub from_folder: bool,
}

pub struct SettingsData {
    pub countries: Vec<CountryRow>,
    /// Every country iptv-org has channels for: (code, name, channels).
    pub all_countries: Vec<(String, String, usize)>,
    pub lists: Vec<ListRow>,
    /// (name, link) of the streams, pages and videos added one by one.
    pub sources: Vec<(String, String)>,
    pub guides: Vec<(String, String)>,
    pub every: u64,
    pub last_check: String,
    pub checking: bool,
    pub open_last: bool,
    pub logos: bool,
    pub lower_on_weak: bool,
    pub autonext: bool,
}

pub struct SettingsView {
    pub root: gtk::Box,
    body: gtk::Box,
    url: gtk::Entry,
    kind: gtk::Label,
    add: gtk::Button,
    name: gtk::Entry,
    /// The link waiting for a name, once Add was pressed on a stream or a page.
    naming: RefCell<Option<String>>,
    country: gtk::Entry,
    sugg: gtk::Box,
    all: RefCell<Vec<(String, String, usize)>>,
    mine: RefCell<Vec<String>>,
    pub on_action: RefCell<Option<Box<dyn Fn(Action)>>>,
}

fn label(text: &str, class: &str) -> gtk::Label {
    let l = gtk::Label::new(Some(text));
    l.add_css_class(class);
    l.set_xalign(0.0);
    l.set_ellipsize(pango::EllipsizeMode::End);
    l
}

/// What a link was recognised as, under the field.
fn kind_hint(t: &str) -> &'static str {
    if t.trim().is_empty() {
        return "";
    }
    match link_kind(t) {
        Some(_) => "",
        None => "Not a link yet",
    }
}

pub fn kind_word(t: &str) -> &'static str {
    match link_kind(t) {
        Some(LinkKind::Playlist) => "Playlist",
        Some(LinkKind::Stream) => "Stream",
        Some(LinkKind::Page) => "Web page",
        Some(LinkKind::Video) => "Video",
        None => "Link",
    }
}

/// A line: its name, what it says under it, and what it ends with.
fn line(title: &str, detail: &str) -> gtk::Box {
    let r = gtk::Box::new(gtk::Orientation::Horizontal, 0);
    r.add_css_class("prow");
    let text = gtk::Box::new(gtk::Orientation::Vertical, 0);
    text.set_hexpand(true);
    text.set_valign(gtk::Align::Center);
    text.append(&label(title, "ptext"));
    if !detail.is_empty() {
        text.append(&label(detail, "pdetail"));
    }
    r.append(&text);
    r
}

fn button(text: &str, class: &str) -> gtk::Button {
    let b = gtk::Button::with_label(text);
    b.add_css_class(class);
    b.set_valign(gtk::Align::Center);
    b
}

impl SettingsView {
    pub fn new() -> Rc<Self> {
        let root = gtk::Box::new(gtk::Orientation::Vertical, 0);
        root.add_css_class("spage");
        let tabs = gtk::Box::new(gtk::Orientation::Horizontal, 0);
        tabs.add_css_class("ptabs");
        let panel = gtk::Box::new(gtk::Orientation::Vertical, 0);
        panel.add_css_class("ppanel");
        panel.set_vexpand(true);
        let body = gtk::Box::new(gtk::Orientation::Vertical, 0);
        body.add_css_class("pbody");
        body.set_halign(gtk::Align::Start);
        let sc = gtk::ScrolledWindow::builder()
            .hscrollbar_policy(gtk::PolicyType::Never)
            .vscrollbar_policy(gtk::PolicyType::External)
            .vexpand(true)
            .child(&body)
            .build();
        panel.append(&sc);
        root.append(&tabs);
        root.append(&panel);
        let url = gtk::Entry::new();
        url.add_css_class("pfield");
        url.set_placeholder_text(Some("Paste a link"));
        url.set_hexpand(true);
        let kind = label("", "phint");
        let add = button("Add", "pbtn");
        add.set_sensitive(false);
        let name = gtk::Entry::new();
        name.add_css_class("pfield");
        name.set_placeholder_text(Some("Name"));
        name.set_hexpand(true);
        let country = gtk::Entry::new();
        country.add_css_class("pfield");
        country.set_placeholder_text(Some("Add a country"));
        country.set_hexpand(true);
        let sugg = gtk::Box::new(gtk::Orientation::Vertical, 0);
        sugg.add_css_class("psugg");
        let me = Rc::new(SettingsView {
            root,
            body,
            url: url.clone(),
            kind,
            add: add.clone(),
            name: name.clone(),
            naming: RefCell::new(None),
            country: country.clone(),
            sugg,
            all: RefCell::new(vec![]),
            mine: RefCell::new(vec![]),
            on_action: RefCell::new(None),
        });
        let w = Rc::downgrade(&me);
        url.connect_changed(move |e| {
            if let Some(me) = w.upgrade() {
                let t = e.text();
                me.kind.set_text(kind_hint(&t));
                me.kind.set_visible(!kind_hint(&t).is_empty());
                // the button says what it will add
                me.add.set_label(match link_kind(&t) {
                    Some(LinkKind::Playlist) => "Add playlist",
                    Some(LinkKind::Stream) => "Add stream",
                    Some(LinkKind::Page) => "Add page",
                    Some(LinkKind::Video) => "Add video",
                    None => "Add",
                });
                me.add.set_sensitive(link_kind(&t).is_some());
            }
        });
        let w = Rc::downgrade(&me);
        url.connect_activate(move |_| {
            if let Some(me) = w.upgrade() {
                me.add_link();
            }
        });
        let w = Rc::downgrade(&me);
        add.connect_clicked(move |_| {
            if let Some(me) = w.upgrade() {
                me.add_link();
            }
        });
        let w = Rc::downgrade(&me);
        name.connect_activate(move |_| {
            if let Some(me) = w.upgrade() {
                me.name_done();
            }
        });
        let w = Rc::downgrade(&me);
        country.connect_changed(move |_| {
            if let Some(me) = w.upgrade() {
                me.fill_suggestions();
            }
        });
        let w = Rc::downgrade(&me);
        country.connect_activate(move |_| {
            if let Some(me) = w.upgrade() {
                if let Some(cc) = me.suggestions().first().map(|c| c.0.clone()) {
                    me.country.set_text("");
                    me.act(Action::AddCountry(cc));
                }
            }
        });
        me
    }

    /// Add on the link: a playlist is added at once; a stream, a page or a
    /// video first asks for a name.
    fn add_link(self: &Rc<Self>) {
        let t = self.url.text().trim().to_string();
        match link_kind(&t) {
            Some(LinkKind::Playlist) => {
                self.url.set_text("");
                self.act(Action::AddList(t));
            }
            Some(_) => {
                self.url.set_text("");
                self.start_naming(&t);
                self.act(Action::Redraw);
                self.name.grab_focus_without_selecting();
                self.name.set_position(-1);
            }
            None => {}
        }
    }

    /// The name step for `link`, its name guessed when it can be: the
    /// file's for a video, the site's for a page.
    pub fn start_naming(&self, link: &str) {
        let guess = match link_kind(link) {
            Some(LinkKind::Video) => std::path::Path::new(link.trim_start_matches("file://")).file_stem().and_then(|s| s.to_str()).unwrap_or("").to_string(),
            Some(LinkKind::Page) => {
                let h = host_of(link);
                let first = h.split('.').next().unwrap_or("").to_string();
                let mut c = first.chars();
                c.next().map(|f| f.to_uppercase().collect::<String>() + c.as_str()).unwrap_or_default()
            }
            _ => String::new(),
        };
        self.name.set_text(&guess);
        *self.naming.borrow_mut() = Some(link.to_string());
    }

    pub fn focus_name(&self) {
        self.name.grab_focus_without_selecting();
        self.name.set_position(-1);
    }

    fn name_done(self: &Rc<Self>) {
        let n = self.name.text().trim().to_string();
        if n.is_empty() {
            return;
        }
        if let Some(link) = self.naming.borrow_mut().take() {
            self.act(Action::AddSource(n, link));
        }
    }

    fn act(&self, a: Action) {
        if let Some(f) = self.on_action.borrow().as_ref() {
            f(a);
        }
    }

    /// The first control, for the keyboard.
    pub fn focus_first(&self) {
        self.body.child_focus(gtk::DirectionType::TabForward);
    }

    /// Countries whose name begins with what is typed, the biggest first.
    fn suggestions(&self) -> Vec<(String, String, usize)> {
        let q = crate::epg::norm(&self.country.text());
        if q.is_empty() {
            return vec![];
        }
        let mine = self.mine.borrow();
        let mut out: Vec<_> = self
            .all
            .borrow()
            .iter()
            .filter(|(cc, name, _)| !mine.iter().any(|m| m.eq_ignore_ascii_case(cc)) && crate::epg::norm(name).starts_with(&q))
            .cloned()
            .collect();
        out.sort_by(|a, b| b.2.cmp(&a.2));
        out.truncate(5);
        out
    }

    fn fill_suggestions(self: &Rc<Self>) {
        while let Some(c) = self.sugg.first_child() {
            self.sugg.remove(&c);
        }
        let typed = !self.country.text().trim().is_empty();
        let found = self.suggestions();
        if typed && found.is_empty() {
            let l = label(if self.all.borrow().is_empty() { "Loading countries…" } else { "No country by that name" }, "phint");
            self.sugg.append(&l);
        }
        for (cc, name, n) in found {
            let b = gtk::Button::new();
            b.add_css_class("psug");
            let r = line(&name, &format!("{n} channels"));
            r.remove_css_class("prow");
            let add = label("Add", "padd");
            r.append(&add);
            b.set_child(Some(&r));
            let w = Rc::downgrade(self);
            b.connect_clicked(move |_| {
                if let Some(me) = w.upgrade() {
                    me.country.set_text("");
                    me.act(Action::AddCountry(cc.clone()));
                }
            });
            self.sugg.append(&b);
        }
    }

    fn switch_line(self: &Rc<Self>, title: &str, detail: &str, on: bool, make: fn(bool) -> Action) -> gtk::Box {
        let r = line(title, detail);
        r.add_css_class("click");
        let sw = gtk::Switch::new();
        sw.set_active(on);
        sw.set_valign(gtk::Align::Center);
        let w = Rc::downgrade(self);
        sw.connect_active_notify(move |s| {
            if let Some(me) = w.upgrade() {
                me.act(make(s.is_active()));
            }
        });
        // the whole line flips it
        let click = gtk::GestureClick::new();
        let s2 = sw.clone();
        click.connect_released(move |g, _, x, y| {
            // a click on the switch itself is the switch's
            let on_switch = g.widget().and_then(|r| r.pick(x, y, gtk::PickFlags::DEFAULT)).is_some_and(|w| w == *s2.upcast_ref::<gtk::Widget>() || w.is_ancestor(&s2));
            if !on_switch {
                s2.set_active(!s2.is_active());
            }
        });
        r.add_controller(click);
        r.append(&sw);
        r
    }

    fn detach(e: &impl IsA<gtk::Widget>) {
        if let Some(p) = e.parent() {
            if let Some(b) = p.downcast_ref::<gtk::Box>() {
                b.remove(e);
            }
        }
    }

    pub fn render(self: &Rc<Self>, page: Page, d: &SettingsData) {
        // the keyboard stays where it was: in a field, or in the page
        let focus = self.root.root().and_then(|r| r.focus());
        let in_url = focus.as_ref().is_some_and(|f| f.is_ancestor(&self.url));
        let in_name = focus.as_ref().is_some_and(|f| f.is_ancestor(&self.name));
        let in_country = focus.as_ref().is_some_and(|f| f.is_ancestor(&self.country));
        let in_page = focus.as_ref().is_some_and(|f| f.is_ancestor(&self.body));
        self.render_page(page, d);
        if in_name && self.name.parent().is_some() {
            self.focus_name();
        } else if in_url && self.url.parent().is_some() {
            self.url.grab_focus_without_selecting();
        } else if in_country && self.country.parent().is_some() {
            self.country.grab_focus_without_selecting();
        } else if in_page {
            self.focus_first();
        }
    }

    fn render_page(self: &Rc<Self>, page: Page, d: &SettingsData) {
        // keep what is being typed across a redraw
        Self::detach(&self.url);
        Self::detach(&self.country);
        Self::detach(&self.kind);
        Self::detach(&self.add);
        Self::detach(&self.name);
        if let Some(p) = self.sugg.parent() {
            if let Some(b) = p.downcast_ref::<gtk::Box>() {
                b.remove(&self.sugg);
            }
        }
        while let Some(c) = self.body.first_child() {
            self.body.remove(&c);
        }
        *self.all.borrow_mut() = d.all_countries.clone();
        *self.mine.borrow_mut() = d.countries.iter().map(|c| c.cc.clone()).collect();
        let b = &self.body;
        let intro = |title: &str, text: &str| {
            b.append(&label(title, "ptitle"));
            if !text.is_empty() {
                let l = label(text, "pdesc");
                l.set_wrap(true);
                l.set_ellipsize(pango::EllipsizeMode::None);
                b.append(&l);
            }
        };
        let rows = gtk::Box::new(gtk::Orientation::Vertical, 0);
        rows.add_css_class("prows");
        match page {
            Page::Countries => {
                intro("Countries", "Each country adds its free channels to the guide.");
                for c in &d.countries {
                    let r = line(&c.name, &c.detail);
                    if d.countries.len() > 1 {
                        let x = button("Remove", "plink");
                        let w = Rc::downgrade(self);
                        let cc = c.cc.clone();
                        x.connect_clicked(move |_| {
                            if let Some(me) = w.upgrade() {
                                me.act(Action::RemoveCountry(cc.clone()));
                            }
                        });
                        r.append(&x);
                    }
                    rows.append(&r);
                }
                b.append(&rows);
                let add = gtk::Box::new(gtk::Orientation::Horizontal, 0);
                add.add_css_class("paddrow");
                let icon = gtk::Image::from_icon_name("list-add-symbolic");
                icon.add_css_class("picon");
                add.append(&icon);
                add.append(&self.country);
                b.append(&add);
                b.append(&self.sugg);
                self.fill_suggestions();
            }
            Page::Playlists => {
                intro("My sources", "Add a playlist, a stream or a web page with a video.");
                for l in &d.lists {
                    let r = line(&l.name, &l.detail);
                    if !l.from_folder {
                        let x = button("Remove", "plink");
                        let w = Rc::downgrade(self);
                        let spec = l.spec.clone();
                        x.connect_clicked(move |_| {
                            if let Some(me) = w.upgrade() {
                                me.act(Action::RemoveList(spec.clone()));
                            }
                        });
                        r.append(&x);
                    }
                    rows.append(&r);
                }
                for (name, link) in &d.sources {
                    let r = line(name, &format!("{} · {}", kind_word(link), host_of(link)));
                    let x = button("Remove", "plink");
                    let w = Rc::downgrade(self);
                    let link = link.clone();
                    x.connect_clicked(move |_| {
                        if let Some(me) = w.upgrade() {
                            me.act(Action::RemoveSource(link.clone()));
                        }
                    });
                    r.append(&x);
                    rows.append(&r);
                }
                b.append(&rows);
                let naming = self.naming.borrow().clone();
                let add = gtk::Box::new(gtk::Orientation::Horizontal, 0);
                add.add_css_class("paddrow");
                match &naming {
                    Some(link) => {
                        add.append(&self.name);
                        let ok = button("Add", "pbtn");
                        let w = Rc::downgrade(self);
                        ok.connect_clicked(move |_| {
                            if let Some(me) = w.upgrade() {
                                me.name_done();
                            }
                        });
                        add.append(&ok);
                        let cancel = button("Cancel", "plink");
                        let w = Rc::downgrade(self);
                        cancel.connect_clicked(move |_| {
                            if let Some(me) = w.upgrade() {
                                me.naming.borrow_mut().take();
                                me.act(Action::Redraw);
                            }
                        });
                        add.append(&cancel);
                        b.append(&add);
                        b.append(&label(&format!("{} · {}", kind_word(link), host_of(link)), "phint"));
                    }
                    None => {
                        add.append(&self.url);
                        add.append(&self.add);
                        b.append(&add);
                        self.kind.set_visible(!self.kind.text().is_empty());
                        b.append(&self.kind);
                    }
                }
                let file = button("Choose a file…", "plink");
                file.set_halign(gtk::Align::Start);
                file.add_css_class("pafter");
                let w = Rc::downgrade(self);
                file.connect_clicked(move |_| {
                    if let Some(me) = w.upgrade() {
                        me.act(Action::ChooseFile);
                    }
                });
                b.append(&file);
                let folder = gtk::Box::new(gtk::Orientation::Vertical, 0);
                folder.add_css_class("prows");
                folder.add_css_class("pgap");
                let r = line("Playlists folder", "Playlists and videos placed here are added too");
                let open = button("Open", "pbtn");
                let w = Rc::downgrade(self);
                open.connect_clicked(move |_| {
                    if let Some(me) = w.upgrade() {
                        me.act(Action::OpenFolder);
                    }
                });
                r.append(&open);
                folder.append(&r);
                b.append(&folder);
            }
            Page::Checks => {
                intro("Channel checks", "Channels that don't answer are hidden from the guide until they do.");
                let r = line("Check automatically", "");
                let seg = gtk::Box::new(gtk::Orientation::Horizontal, 0);
                seg.add_css_class("seg");
                seg.set_valign(gtk::Align::Center);
                let mut first: Option<gtk::ToggleButton> = None;
                for (h, text) in [(1u64, "Every hour"), (6, "Every 6 hours"), (24, "Once a day")] {
                    let t = gtk::ToggleButton::with_label(text);
                    t.add_css_class("segb");
                    if let Some(f) = &first {
                        t.set_group(Some(f));
                    } else {
                        first = Some(t.clone());
                    }
                    t.set_active(d.every == h);
                    let w = Rc::downgrade(self);
                    t.connect_toggled(move |t| {
                        if t.is_active() {
                            if let Some(me) = w.upgrade() {
                                me.act(Action::Every(h));
                            }
                        }
                    });
                    seg.append(&t);
                }
                r.append(&seg);
                rows.append(&r);
                let r = line("Last check", if d.checking { "Checking channels…" } else { &d.last_check });
                let now = button("Check now", "pbtn");
                now.set_sensitive(!d.checking);
                let w = Rc::downgrade(self);
                now.connect_clicked(move |_| {
                    if let Some(me) = w.upgrade() {
                        me.act(Action::CheckNow);
                    }
                });
                r.append(&now);
                rows.append(&r);
                b.append(&rows);
            }
            Page::Listings => {
                intro("TV listings", "Programme times in the guide come from here.");
                if d.guides.is_empty() {
                    b.append(&label("None for the countries you added.", "phint"));
                }
                for (name, detail) in &d.guides {
                    rows.append(&line(name, detail));
                }
                b.append(&rows);
            }
            Page::Playback | Page::Search | Page::Guide | Page::Continue | Page::Shows => {
                intro("Playback", "");
                rows.append(&self.switch_line("Open on the last channel", "", d.open_last, Action::OpenLast));
                rows.append(&self.switch_line("Show channel logos", "", d.logos, Action::Logos));
                rows.append(&self.switch_line("Lower quality on a weak connection", "Fewer cuts, a softer picture", d.lower_on_weak, Action::LowerOnWeak));
                rows.append(&self.switch_line("Play the next episode automatically", "", d.autonext, Action::AutoNext));
                b.append(&rows);
            }
        }
    }
}
