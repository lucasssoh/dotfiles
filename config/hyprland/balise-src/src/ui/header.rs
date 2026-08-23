//! Header: title + WiFi radio switch. Simplified from
//! orbit-vendor/src/ui/header.rs -- no tab bar yet (only WiFi exists,
//! see the project plan's roadmap for Ethernet/Bluetooth), no wired
//! button.

use gtk4::prelude::*;
use gtk4::{self as gtk, Orientation};
use std::cell::RefCell;
use std::rc::Rc;

#[derive(Clone)]
pub struct Header {
    container: gtk::Box,
    power_switch: gtk::Switch,
    is_programmatic_update: Rc<RefCell<bool>>,
}

impl Header {
    pub fn new() -> Self {
        let container = gtk::Box::builder()
            .orientation(Orientation::Horizontal)
            .css_classes(["balise-header"])
            .spacing(12)
            .build();

        let title = gtk::Label::builder()
            .label("WiFi")
            .css_classes(["balise-title"])
            .halign(gtk::Align::Start)
            .hexpand(true)
            .build();

        // sensitive(false) until the first WifiPowerState event arrives --
        // same as Orbit, avoids the switch looking interactive before we
        // actually know the radio's real state.
        let power_switch = gtk::Switch::builder()
            .css_classes(["balise-toggle-switch"])
            .active(false)
            .sensitive(false)
            .valign(gtk::Align::Center)
            .build();

        container.append(&title);
        container.append(&power_switch);

        Self {
            container,
            power_switch,
            is_programmatic_update: Rc::new(RefCell::new(false)),
        }
    }

    pub fn widget(&self) -> &gtk::Box {
        &self.container
    }

    /// Updates the switch to reflect NetworkManager's real radio state
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
}
