//! Header: a title-only "home" row, or a "subpage" row (back arrow +
//! title + optional radio switch) -- the tab bar (WiFi/Bluetooth/
//! Ethernet buttons) is gone, replaced by HomeView's own tiles (see
//! ui/home.rs and the project plan: Balise is dropping the tab-header
//! concept for a Control-Center-style home page). Adapted from
//! orbit-vendor/src/ui/header.rs (WiFi/Bluetooth/VPN there -- VPN
//! dropped, Ethernet gets its own section here instead of Orbit's side
//! "wired" button + overlay).
//!
//! "subpage" now covers what used to be two separate modes: the tab
//! header's own title+switch row, AND the endpoint detail page's plain
//! back+title row. Both need a back arrow and a title; only the WiFi/
//! Bluetooth SECTIONS also need the radio switch (Ethernet has no
//! radio-enable concept, and the endpoint detail page never showed one
//! either) -- `power` on `set_subpage_mode` is what tells them apart, one
//! row/one set of widgets either way, no more juggling two different
//! back-row shapes for what's visually the same "‹ title" bar.

use gtk4::prelude::*;
use gtk4::{self as gtk, glib, Orientation};
use std::cell::RefCell;
use std::rc::Rc;

#[derive(Clone)]
pub struct Header {
    container: gtk::Box,
    power_switch: gtk::Switch,
    power_box: gtk::Box,
    is_programmatic_update: Rc<RefCell<bool>>,
    /// Home mode (a little live clock, no back arrow) vs. subpage mode
    /// (back arrow + title + optional switch) live in a Stack rather
    /// than being shown/hidden, so the header keeps a constant height
    /// across both -- see `set_power_visible`'s own note on the same bug
    /// for why that matters.
    mode_stack: gtk::Stack,
    back_button: gtk::Button,
    back_title: gtk::Label,
}

impl Header {
    pub fn new() -> Self {
        // margin_bottom: a little more breathing room before whatever's
        // below (the home tiles, or a section's own list) -- asked for
        // after the clock grew to 2.6em, which left it sitting right on
        // top of the content underneath.
        let container = gtk::Box::builder()
            .orientation(Orientation::Vertical)
            .css_classes(["balise-header"])
            .spacing(8)
            .margin_bottom(14)
            .build();

        // ---- home mode: a little live clock, anchored right --------------
        // Replaced the plain "Balise" title -- asked for a two-row
        // clock instead: HH:MM large, weekday/month/day small underneath,
        // both right-aligned (not left, where the title used to sit).
        // Day/month spelled out by hand rather than through
        // glib::DateTime::format's locale-aware "%a"/"%b" (which would
        // follow the system's fr_FR locale -- "ven. 28 août") -- pinned
        // to English abbreviations, same reasoning and the exact same
        // "Fri Aug 28" shape as the bar's own Clock.qml used before it
        // was simplified back down to a bare time.
        let clock_time = gtk::Label::builder().label("").css_classes(["balise-home-clock-time"]).halign(gtk::Align::End).build();
        let clock_date = gtk::Label::builder().label("").css_classes(["balise-home-clock-date"]).halign(gtk::Align::End).build();
        // margin_end: "décale l'ensemble un peu vers la gauche" -- End-
        // aligned still means flush against the panel's own right edge
        // otherwise, this is what actually pulls it inward from there.
        let home_clock = gtk::Box::builder()
            .orientation(Orientation::Vertical)
            .spacing(0)
            .halign(gtk::Align::End)
            .hexpand(true)
            .margin_end(10)
            .build();
        home_clock.append(&clock_time);
        home_clock.append(&clock_date);

        {
            let clock_time = clock_time.clone();
            let clock_date = clock_date.clone();
            let tick = move || {
                let day_names = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"];
                let month_names = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
                if let Ok(now) = glib::DateTime::now_local() {
                    clock_time.set_label(&format!("{:02}:{:02}", now.hour(), now.minute()));
                    let day = day_names.get((now.day_of_week() - 1) as usize).copied().unwrap_or("");
                    let month = month_names.get((now.month() - 1) as usize).copied().unwrap_or("");
                    clock_date.set_label(&format!("{} {} {}", day, month, now.day_of_month()));
                }
            };
            tick();
            glib::timeout_add_local(std::time::Duration::from_secs(1), move || {
                tick();
                glib::ControlFlow::Continue
            });
        }

        // ---- subpage mode: ‹ title ... [switch] -------------------------
        let power_switch = gtk::Switch::builder()
            .css_classes(["balise-toggle-switch"])
            .active(false)
            .sensitive(false)
            .valign(gtk::Align::Center)
            .build();
        let power_box = gtk::Box::builder().orientation(Orientation::Horizontal).valign(gtk::Align::Center).build();
        power_box.append(&power_switch);

        let back_button = gtk::Button::builder().css_classes(["balise-back-button", "flat"]).build();
        back_button.set_child(Some(&super::icon::icon_label(super::icon::CARET_LEFT)));
        let back_title = gtk::Label::builder().label("").css_classes(["balise-back-title"]).halign(gtk::Align::Start).hexpand(true).build();
        back_title.set_ellipsize(gtk::pango::EllipsizeMode::End);

        let subpage_row = gtk::Box::builder().orientation(Orientation::Horizontal).spacing(8).css_classes(["balise-back-row"]).build();
        subpage_row.append(&back_button);
        subpage_row.append(&back_title);
        subpage_row.append(&power_box);

        let mode_stack = gtk::Stack::builder()
            .vhomogeneous(true)
            .transition_type(gtk::StackTransitionType::Crossfade)
            .transition_duration(120)
            .build();
        mode_stack.add_named(&home_clock, Some("home"));
        mode_stack.add_named(&subpage_row, Some("subpage"));
        mode_stack.set_visible_child_name("home");
        container.append(&mode_stack);

        Self {
            container,
            power_switch,
            power_box,
            is_programmatic_update: Rc::new(RefCell::new(false)),
            mode_stack,
            back_button,
            back_title,
        }
    }

    pub fn back_button(&self) -> &gtk::Button {
        &self.back_button
    }

    pub fn set_home_mode(&self) {
        self.mode_stack.set_visible_child_name("home");
    }

    /// Enters "‹ title" mode. `power` shows/hides the radio switch --
    /// true for the WiFi/Bluetooth sections, false for Ethernet's
    /// section and for the true endpoint-detail page (a specific access
    /// point/device/profile), neither of which has a radio-enable
    /// concept of its own to toggle here.
    pub fn set_subpage_mode(&self, title: &str, power: bool) {
        self.back_title.set_label(title);
        self.set_power_visible(power);
        self.mode_stack.set_visible_child_name("subpage");
    }

    pub fn widget(&self) -> &gtk::Box {
        &self.container
    }

    /// Updates the switch to reflect the current section's real radio
    /// state without re-triggering `connect_active_notify` as if the
    /// user had flipped it (see `is_programmatic_update`).
    pub fn set_power_state(&self, enabled: bool) {
        *self.is_programmatic_update.borrow_mut() = true;
        self.power_switch.set_sensitive(true);
        self.power_switch.set_active(enabled);
        *self.is_programmatic_update.borrow_mut() = false;
    }

    pub fn is_programmatic_update(&self) -> bool {
        *self.is_programmatic_update.borrow()
    }

    pub fn power_switch(&self) -> &gtk::Switch {
        &self.power_switch
    }

    /// Hides the radio switch WITHOUT removing it from the layout.
    ///
    /// `set_visible(false)` was the obvious thing to write here and it
    /// caused a real glitch: dropping the widget shrank the header,
    /// which shrank the whole window (its `height_request` is only a
    /// minimum), and since the panel is anchored to the top of the
    /// screen the bottom edge jumped. Crossfading to/from Ethernet then
    /// showed the content lurching vertically -- measured at 492px tall
    /// on WiFi/Bluetooth versus 480px on Ethernet.
    ///
    /// Opacity keeps the row allocated, so every subpage measures the
    /// same height regardless of whether its switch shows. `can_target
    /// (false)` is what stops an invisible switch from still swallowing
    /// clicks.
    fn set_power_visible(&self, visible: bool) {
        self.power_box.set_opacity(if visible { 1.0 } else { 0.0 });
        self.power_box.set_can_target(visible);
    }
}
