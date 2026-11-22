//! The list of keys (":" or "?"; not "h", which is an arrow), and the small
//! reminder of that key which shows when a key does nothing.
//!
//! Seven blocks in three columns; the one that matches what is on screen
//! (watching, the guide, its tabs, the menu on its left, a reminder card)
//! stands out.

use crate::keys::{self, Action};
use gtk4 as gtk;
use gtk::prelude::*;

#[derive(Clone, Copy, PartialEq, Eq)]
pub enum Context {
    Watching,
    Guide,
    Tabs,
    Column,
    Shows,
    Streaming,
    Reminder,
}

pub struct Help {
    pub root: gtk::Box,
    blocks: Vec<(Option<Context>, gtk::Box)>,
    pub hint: gtk::Box,
}

/// A block of hints, each drawn for the keyboard or the pad in hand.
fn block(title: &str, rows: &[(Action, &str)]) -> gtk::Box {
    let b = gtk::Box::new(gtk::Orientation::Vertical, 0);
    b.add_css_class("hblock");
    let t = gtk::Label::new(Some(title));
    t.add_css_class("htitle");
    t.set_xalign(0.0);
    b.append(&t);
    for (a, v) in rows {
        let row = keys::hint(*a, v, "act");
        row.add_css_class("hrow");
        b.append(&row);
    }
    b
}

/// The mouse's, written out.
fn mouse_block(rows: &[(&str, &str)]) -> gtk::Box {
    let b = gtk::Box::new(gtk::Orientation::Vertical, 0);
    b.add_css_class("hblock");
    let t = gtk::Label::new(Some("MOUSE"));
    t.add_css_class("htitle");
    t.set_xalign(0.0);
    b.append(&t);
    for (k, v) in rows {
        let row = gtk::Box::new(gtk::Orientation::Horizontal, 0);
        row.add_css_class("hrow");
        let key = gtk::Label::new(Some(k));
        key.add_css_class("kbd");
        let act = gtk::Label::new(Some(v));
        act.add_css_class("act");
        act.set_xalign(0.0);
        row.append(&key);
        row.append(&act);
        b.append(&row);
    }
    b
}

impl Help {
    /// `key`: the key to show for the list, ":" where it needs no Shift.
    pub fn new(key: &str) -> Self {
        let root = gtk::Box::new(gtk::Orientation::Vertical, 0);
        root.add_css_class("help");
        root.add_css_class("glass");
        root.set_halign(gtk::Align::Center);
        root.set_valign(gtk::Align::Center);
        root.set_can_target(false);
        let title = gtk::Label::new(Some("Keys"));
        title.add_css_class("hhead");
        title.set_xalign(0.0);
        root.append(&title);

        let watching = block(
            "WATCHING",
            &[
                (Action::Step, "Channel info, then the guide"),
                (Action::UpDown, "Previous / next channel in the tab"),
                (Action::Digits, "Go to a channel number"),
                (Action::Guide, "Guide"),
                (Action::Search, "Search"),
                (Action::Settings, "Settings"),
                (Action::Info, "Channel info"),
                (Action::Fav, "Favourite on / off"),
                (Action::PrevChannel, "Previous channel"),
            ],
        );
        let streaming = block(
            "WATCHING A SHOW",
            &[
                (Action::Ok, "Pause / play"),
                (Action::SeekSmall, "Back / forward 10 s"),
                (Action::SeekBig, "Back / forward 1 min"),
                (Action::UpDown, "Previous / next episode"),
                (Action::Home, "From the beginning"),
                (Action::Step, "Info, then the show"),
            ],
        );
        let reminder = block("REMINDER CARD", &[(Action::Ok, "Watch that channel"), (Action::Back, "Dismiss")]);
        let guide = block(
            "GUIDE",
            &[
                (Action::UpDown, "Channel"),
                (Action::LeftRight, "Earlier / later programme"),
                (Action::Left, "Back to the menu, from the first programme"),
                (Action::PageUpDown, "Six channels up / down"),
                (Action::Tabs, "Next / previous tab"),
                (Action::Home, "Back to now"),
                (Action::Ok, "Watch, or set a reminder if it is later"),
                (Action::Fav, "Favourite on / off"),
                (Action::Back, "Close"),
            ],
        );
        let tabs = block("TABS", &[(Action::Up, "Up to the tabs, from the first channel"), (Action::LeftRight, "Category"), (Action::Ok, "Back to the guide")]);
        let column = block("MENU", &[(Action::UpDown, "Move through the menu"), (Action::Ok, "Open the page"), (Action::Back, "Back to the menu, then close")]);
        let shows = block(
            "SHOWS",
            &[
                (Action::Arrows, "Pick a show or an episode"),
                (Action::Ok, "Open, then play or resume"),
                (Action::LeftRight, "Season or arc, in a show"),
                (Action::Home, "Play from the beginning"),
                (Action::More, "More actions"),
                (Action::Back, "Back to the shows, then the menu"),
            ],
        );
        let anywhere = block(
            "ANYWHERE",
            &[
                (Action::Arrows, "Arrows"),
                (Action::Keys, "This list"),
                (Action::FullScreen, "Full screen on / off"),
                (Action::SuperG, "Bring the TV here, or open the guide"),
            ],
        );
        let mouse = mouse_block(&[
            ("Click", "Watch a programme or a channel; pause a video"),
            ("Double-click", "Full screen on / off"),
            ("Wheel", "Scroll; over the hours, through time"),
        ]);

        let cols = gtk::Box::new(gtk::Orientation::Horizontal, 0);
        let cols_of: [Vec<&gtk::Box>; 3] = [vec![&watching, &streaming, &reminder], vec![&guide, &tabs, &column], vec![&shows, &anywhere, &mouse]];
        for group in cols_of {
            let col = gtk::Box::new(gtk::Orientation::Vertical, 0);
            col.add_css_class("hcol");
            for b in group {
                col.append(b);
            }
            cols.append(&col);
        }
        root.append(&cols);

        let hint = gtk::Box::new(gtk::Orientation::Horizontal, 0);
        hint.add_css_class("khint");
        hint.add_css_class("glass");
        hint.set_halign(gtk::Align::End);
        hint.set_valign(gtk::Align::End);
        hint.set_can_target(false);
        let _ = key;
        hint.append(&keys::hint(Action::Keys, "Keys", "act"));

        let blocks = vec![
            (Some(Context::Watching), watching),
            (Some(Context::Reminder), reminder),
            (Some(Context::Streaming), streaming),
            (Some(Context::Guide), guide),
            (Some(Context::Tabs), tabs),
            (Some(Context::Column), column),
            (Some(Context::Shows), shows),
            (None, anywhere),
            (None, mouse),
        ];
        Help { root, blocks, hint }
    }

    pub fn set_open(&self, open: bool) {
        if open {
            self.root.add_css_class("show");
        } else {
            self.root.remove_css_class("show");
        }
    }

    /// The block that matches what is on screen stands out.
    pub fn set_context(&self, ctx: Context) {
        for (c, b) in &self.blocks {
            if *c == Some(ctx) {
                b.add_css_class("now");
            } else {
                b.remove_css_class("now");
            }
        }
    }

    pub fn is_open(&self) -> bool {
        self.root.has_css_class("show")
    }
}
