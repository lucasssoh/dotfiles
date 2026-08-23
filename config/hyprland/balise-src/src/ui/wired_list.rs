//! Ethernet tab (Phase 2): one row per wired device/profile, with a
//! Connect/Disconnect button and an autoconnect switch -- no separate
//! "saved" overlay needed here (unlike WiFi, there's usually just one
//! wired interface), matching the plan's "second stack child" design
//! rather than Orbit's side-button-plus-overlay treatment.

use gtk4::{self as gtk, glib, prelude::*, Orientation};
use std::cell::RefCell;
use std::rc::Rc;

use crate::dbus::WiredProfile;

#[derive(Clone)]
pub struct WiredList {
    container: gtk::Box,
    list_box: gtk::Box,
    on_connect: Rc<RefCell<Option<Rc<dyn Fn(WiredProfile)>>>>,
    on_autoconnect_toggle: Rc<RefCell<Option<Rc<dyn Fn(String, bool)>>>>,
    connecting_device: Rc<RefCell<Option<String>>>,
}

impl WiredList {
    pub fn new() -> Self {
        let container = gtk::Box::builder().orientation(Orientation::Vertical).vexpand(true).hexpand(true).build();

        let scrolled = gtk::ScrolledWindow::builder()
            .vexpand(true)
            .hexpand(true)
            .hscrollbar_policy(gtk::PolicyType::Never)
            .min_content_height(280)
            .css_classes(["balise-scrolled"])
            .build();

        let list_box = gtk::Box::builder().orientation(Orientation::Vertical).css_classes(["balise-list"]).build();
        scrolled.set_child(Some(&list_box));
        container.append(&scrolled);

        let list = Self {
            container,
            list_box,
            on_connect: Rc::new(RefCell::new(None)),
            on_autoconnect_toggle: Rc::new(RefCell::new(None)),
            connecting_device: Rc::new(RefCell::new(None)),
        };
        list.show_loading();
        list
    }

    fn show_loading(&self) {
        let placeholder = gtk::Label::builder().label("Loading wired devices...").css_classes(["balise-placeholder"]).build();
        self.list_box.append(&placeholder);
    }

    pub fn set_profiles(&self, profiles: Vec<WiredProfile>) {
        while let Some(child) = self.list_box.first_child() {
            self.list_box.remove(&child);
        }

        if profiles.is_empty() {
            let placeholder = gtk::Label::builder().label("No wired devices found").css_classes(["balise-placeholder"]).build();
            self.list_box.append(&placeholder);
            return;
        }

        // No named sub-sections here (usually just one wired interface),
        // but still one unified card rather than per-row borders --
        // tinted "connected" as soon as any profile in it is active.
        let any_active = profiles.iter().any(|p| p.is_active);
        let card = super::section::section_card(if any_active { &["connected"] } else { &[] });
        for profile in profiles {
            card.append(&self.create_row(profile));
        }
        self.list_box.append(&card);
    }

    fn create_row(&self, profile: WiredProfile) -> gtk::Box {
        let classes: Vec<&str> = if profile.is_active { vec!["balise-network-row", "connected"] } else { vec!["balise-network-row"] };

        let row = gtk::Box::builder().orientation(Orientation::Horizontal).spacing(12).css_classes(classes).build();

        let glyph = if profile.is_active || profile.has_carrier { super::icon::PLUGS_CONNECTED } else { super::icon::PLUGS };
        let icon = super::icon::icon_label(glyph);
        icon.add_css_class(if profile.is_active { "balise-icon-accent" } else { "balise-signal-icon" });
        icon.set_valign(gtk::Align::Center);
        row.append(&icon);

        let info_box = gtk::Box::builder().orientation(Orientation::Vertical).spacing(2).hexpand(true).valign(gtk::Align::Center).build();

        let name = gtk::Label::builder().label(&profile.name).css_classes(["balise-ssid"]).halign(gtk::Align::Start).build();
        name.set_ellipsize(gtk::pango::EllipsizeMode::End);
        info_box.append(&name);

        let status_text = if profile.is_active {
            let speed = if profile.speed > 0 { format!(" · {} Mb/s", profile.speed) } else { String::new() };
            format!("{}{}{}", profile.device_name, speed, if profile.ip4_address.is_empty() { String::new() } else { format!(" · {}", profile.ip4_address) })
        } else if profile.has_carrier {
            format!("{} · Cable connected", profile.device_name)
        } else {
            format!("{} · No cable", profile.device_name)
        };
        let status = gtk::Label::builder().label(&status_text).css_classes(["balise-status"]).halign(gtk::Align::Start).build();
        info_box.append(&status);
        row.append(&info_box);

        let is_connecting = self.connecting_device.borrow().as_deref() == Some(&profile.device_path);
        if is_connecting {
            let spinner = gtk::Spinner::builder().spinning(true).build();
            spinner.start();
            row.append(&spinner);
        } else {
            let action_label = if profile.is_active { "Disconnect" } else { "Connect" };
            let classes: Vec<&str> =
                if profile.is_active { vec!["balise-button", "flat"] } else { vec!["balise-button", "primary", "flat"] };
            let action_btn = gtk::Button::builder().label(action_label).css_classes(classes).sensitive(profile.has_carrier || profile.is_active).build();

            let on_connect = self.on_connect.clone();
            let profile_clone = profile.clone();
            action_btn.connect_clicked(move |_| {
                if let Some(cb) = on_connect.borrow().as_ref() {
                    cb(profile_clone.clone());
                }
            });
            row.append(&action_btn);

            let autoconnect_switch = gtk::Switch::builder()
                .active(profile.autoconnect)
                .css_classes(["balise-toggle-switch"])
                .valign(gtk::Align::Center)
                .tooltip_text("Toggle automatic connection")
                .build();
            if !profile.connection_path.is_empty() {
                let path = profile.connection_path.clone();
                let on_toggle = self.on_autoconnect_toggle.clone();
                let is_user_action = Rc::new(RefCell::new(false));
                let is_user_action_clone = is_user_action.clone();
                glib::timeout_add_local(std::time::Duration::from_millis(100), move || {
                    *is_user_action_clone.borrow_mut() = true;
                    glib::ControlFlow::Break
                });
                autoconnect_switch.connect_state_notify(move |switch| {
                    if *is_user_action.borrow() {
                        if let Some(cb) = on_toggle.borrow().as_ref() {
                            cb(path.clone(), switch.is_active());
                        }
                    }
                });
            } else {
                autoconnect_switch.set_sensitive(false);
            }
            row.append(&autoconnect_switch);
        }

        row
    }

    pub fn set_connecting(&self, device_path: Option<String>) {
        *self.connecting_device.borrow_mut() = device_path;
    }

    pub fn widget(&self) -> &gtk::Box {
        &self.container
    }

    pub fn set_on_connect<F: Fn(WiredProfile) + 'static>(&self, callback: F) {
        *self.on_connect.borrow_mut() = Some(Rc::new(callback));
    }

    pub fn set_on_autoconnect_toggle<F: Fn(String, bool) + 'static>(&self, callback: F) {
        *self.on_autoconnect_toggle.borrow_mut() = Some(Rc::new(callback));
    }
}
