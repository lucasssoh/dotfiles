//! Header: title + tab bar (WiFi/Bluetooth/Ethernet) + radio switch.
//! Adapted from orbit-vendor/src/ui/header.rs (WiFi/Bluetooth/VPN there
//! -- VPN dropped, Ethernet gets its own tab here instead of Orbit's
//! side "wired" button + overlay, per the project plan). The switch is
//! shared across tabs and re-labeled per tab (Ethernet has no
//! radio-enable concept, so it's hidden there, matching how Orbit hides
//! it for its own "vpn" tab).

use gtk4::prelude::*;
use gtk4::{self as gtk, Orientation};
use std::cell::RefCell;
use std::rc::Rc;

#[derive(Clone)]
pub struct Header {
    container: gtk::Box,
    wifi_tab: gtk::Button,
    bluetooth_tab: gtk::Button,
    ethernet_tab: gtk::Button,
    power_switch: gtk::Switch,
    power_box: gtk::Box,
    power_label: gtk::Label,
    is_programmatic_update: Rc<RefCell<bool>>,
    /// Detail mode (see `set_detail_mode`): the tab bar and radio switch
    /// are swapped out for a back arrow + the endpoint's name. They live
    /// in a Stack rather than being shown/hidden, so the header keeps a
    /// constant height across both modes -- see `set_detail_mode`.
    mode_stack: gtk::Stack,
    back_button: gtk::Button,
    back_title: gtk::Label,
}

impl Header {
    pub fn new() -> Self {
        let container = gtk::Box::builder()
            .orientation(Orientation::Vertical)
            .css_classes(["balise-header"])
            .spacing(8)
            .build();

        let title_row = gtk::Box::builder().orientation(Orientation::Horizontal).spacing(12).build();

        let spacer = gtk::Box::builder().hexpand(true).build();

        let power_switch = gtk::Switch::builder()
            .css_classes(["balise-toggle-switch"])
            .active(false)
            .sensitive(false)
            .valign(gtk::Align::Center)
            .build();

        let power_label = gtk::Label::builder().label("WiFi").css_classes(["balise-status"]).build();

        let power_box = gtk::Box::builder().orientation(Orientation::Horizontal).spacing(8).valign(gtk::Align::Center).build();
        power_box.append(&power_label);
        power_box.append(&power_switch);

        title_row.append(&spacer);
        title_row.append(&power_box);

        let tab_bar = gtk::Box::builder().orientation(Orientation::Horizontal).css_classes(["balise-tab-bar"]).homogeneous(true).build();

        let wifi_tab = gtk::Button::builder().label("WiFi").css_classes(["balise-tab", "flat", "active"]).hexpand(true).build();
        let bluetooth_tab = gtk::Button::builder().label("Bluetooth").css_classes(["balise-tab", "flat"]).hexpand(true).build();
        let ethernet_tab = gtk::Button::builder().label("Ethernet").css_classes(["balise-tab", "flat"]).hexpand(true).build();

        // Visual order matches the quickshell bar's own icon order
        // (Bluetooth, Network/WiFi, Ethernet -- see shell.qml's
        // connectivity Row) rather than this struct's field order, which
        // stays wifi-first (that's still the default active tab).
        tab_bar.append(&bluetooth_tab);
        tab_bar.append(&wifi_tab);
        tab_bar.append(&ethernet_tab);

        // Detail mode's replacement row: "‹ <endpoint name>". Built
        // once and kept hidden rather than created on demand, so
        // entering/leaving a detail page is two set_visible calls.
        let back_row = gtk::Box::builder()
            .orientation(Orientation::Horizontal)
            .spacing(8)
            .css_classes(["balise-back-row"])
            .visible(false)
            .build();
        let back_button = gtk::Button::builder().css_classes(["balise-back-button", "flat"]).build();
        back_button.set_child(Some(&super::icon::icon_label(super::icon::CARET_LEFT)));
        back_button.set_tooltip_text(Some("Back"));
        let back_title = gtk::Label::builder().label("").css_classes(["balise-back-title"]).halign(gtk::Align::Start).hexpand(true).build();
        back_title.set_ellipsize(gtk::pango::EllipsizeMode::End);
        back_row.append(&back_button);
        back_row.append(&back_title);

        // Tab mode and detail mode go in a Stack, not
        // append + set_visible. A Stack is vhomogeneous, so the header
        // measures the taller of the two modes at all times -- hiding a
        // row instead would shrink the header, and with it the whole
        // window (see set_power_visible's note on the same bug).
        let tabs_mode = gtk::Box::builder().orientation(Orientation::Vertical).spacing(8).build();
        tabs_mode.append(&tab_bar);
        tabs_mode.append(&title_row);
        back_row.set_visible(true);

        let mode_stack = gtk::Stack::builder()
            .vhomogeneous(true)
            .transition_type(gtk::StackTransitionType::Crossfade)
            .transition_duration(120)
            .build();
        mode_stack.add_named(&tabs_mode, Some("tabs"));
        mode_stack.add_named(&back_row, Some("detail"));
        mode_stack.set_visible_child_name("tabs");
        container.append(&mode_stack);

        Self {
            container,
            wifi_tab,
            bluetooth_tab,
            ethernet_tab,
            power_switch,
            power_box,
            power_label,
            is_programmatic_update: Rc::new(RefCell::new(false)),
            mode_stack,
            back_button,
            back_title,
        }
    }

    pub fn back_button(&self) -> &gtk::Button {
        &self.back_button
    }

    /// `Some(name)` swaps the tab bar + radio switch for "‹ name";
    /// `None` restores them. The tab bar keeps whichever tab was active,
    /// so leaving the detail page lands back where the user came from
    /// without re-tinting anything.
    pub fn set_detail_mode(&self, name: Option<&str>) {
        match name {
            Some(name) => {
                self.back_title.set_label(name);
                self.mode_stack.set_visible_child_name("detail");
            }
            None => self.mode_stack.set_visible_child_name("tabs"),
        }
    }

    pub fn widget(&self) -> &gtk::Box {
        &self.container
    }

    /// Updates the switch to reflect the current tab's real radio state
    /// without re-triggering `connect_active_notify` as if the user had
    /// flipped it (see `is_programmatic_update`).
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

    pub fn wifi_tab(&self) -> &gtk::Button {
        &self.wifi_tab
    }

    pub fn bluetooth_tab(&self) -> &gtk::Button {
        &self.bluetooth_tab
    }

    pub fn ethernet_tab(&self) -> &gtk::Button {
        &self.ethernet_tab
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
    /// Opacity keeps the row allocated, so all three tabs are exactly
    /// the same height. `can_target(false)` is what stops an invisible
    /// switch from still swallowing clicks.
    fn set_power_visible(&self, visible: bool) {
        self.power_box.set_opacity(if visible { 1.0 } else { 0.0 });
        self.power_box.set_can_target(visible);
    }

    /// Adapted from orbit-vendor/src/ui/header.rs:155-180. Ethernet has
    /// no radio-enable concept (NetworkManager's per-device "managed"
    /// state isn't a user-facing toggle the way WiFi/Bluetooth radios
    /// are), so the power switch is hidden there entirely -- same
    /// treatment Orbit gives its own "vpn" tab.
    pub fn set_tab(&self, tab: &str) {
        self.wifi_tab.remove_css_class("active");
        self.bluetooth_tab.remove_css_class("active");
        self.ethernet_tab.remove_css_class("active");

        match tab {
            "wifi" => {
                self.wifi_tab.add_css_class("active");
                self.set_power_visible(true);
                self.power_label.set_label("WiFi");
            }
            "bluetooth" => {
                self.bluetooth_tab.add_css_class("active");
                self.set_power_visible(true);
                self.power_label.set_label("Bluetooth");
            }
            "ethernet" => {
                self.ethernet_tab.add_css_class("active");
                self.set_power_visible(false);
            }
            _ => {}
        }
    }
}
