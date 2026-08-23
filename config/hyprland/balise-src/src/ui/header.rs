//! Header: title + tab bar (WiFi/Bluetooth/Ethernet) + radio switch.
//! Adapted from orbit-vendor/src/ui/header.rs (WiFi/Bluetooth/VPN there
//! -- VPN dropped, Ethernet gets its own tab here instead of Orbit's
//! side "wired" button + overlay, per the project plan). The switch is
//! shared across tabs and re-labeled/hidden per tab (Ethernet has no
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

        container.append(&tab_bar);
        container.append(&title_row);

        Self {
            container,
            wifi_tab,
            bluetooth_tab,
            ethernet_tab,
            power_switch,
            power_box,
            power_label,
            is_programmatic_update: Rc::new(RefCell::new(false)),
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
                self.power_box.set_visible(true);
                self.power_label.set_label("WiFi");
            }
            "bluetooth" => {
                self.bluetooth_tab.add_css_class("active");
                self.power_box.set_visible(true);
                self.power_label.set_label("Bluetooth");
            }
            "ethernet" => {
                self.ethernet_tab.add_css_class("active");
                self.power_box.set_visible(false);
            }
            _ => {}
        }
    }
}
