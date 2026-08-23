//! Saved-networks list (shown in an overlay revealer, not a stack page --
//! see window.rs): autoconnect switch + gear button per row. Adapted
//! from orbit-vendor/src/ui/saved_networks_list.rs. The row's Forget
//! button moved into the shared detail page (ui/detail.rs) along with
//! every other destructive action.

use gtk4::prelude::*;
use gtk4::{self as gtk, glib, Orientation};
use std::cell::RefCell;
use std::rc::Rc;

use crate::dbus::SavedNetwork;

#[derive(Clone)]
pub struct SavedList {
    container: gtk::Box,
    list_box: gtk::Box,
    on_autoconnect_toggle: Rc<RefCell<Option<Rc<dyn Fn(String, bool)>>>>,
    on_show_detail: Rc<RefCell<Option<Rc<dyn Fn(String)>>>>,
}

impl SavedList {
    pub fn new() -> Self {
        let container = gtk::Box::builder()
            .orientation(Orientation::Vertical)
            .css_classes(["balise-saved-list-container"])
            .hexpand(true)
            .vexpand(true)
            .build();

        let scrolled = gtk::ScrolledWindow::builder()
            .vexpand(true)
            .hexpand(true)
            .hscrollbar_policy(gtk::PolicyType::Never)
            .vscrollbar_policy(gtk::PolicyType::External)
            .min_content_height(320)
            .min_content_width(320)
            .css_classes(["balise-scrolled"])
            .build();

        let list_box = gtk::Box::builder()
            .orientation(Orientation::Vertical)
            .css_classes(["balise-list"])
            .focusable(true)
            .vexpand(true)
            .build();

        scrolled.set_child(Some(&list_box));
        container.append(&scrolled);

        let list = Self {
            container,
            list_box,
            on_autoconnect_toggle: Rc::new(RefCell::new(None)),
            on_show_detail: Rc::new(RefCell::new(None)),
        };
        list.show_loading();
        list
    }

    fn show_loading(&self) {
        let placeholder = gtk::Label::builder()
            .label("Loading saved networks...")
            .css_classes(["balise-placeholder"])
            .build();
        self.list_box.append(&placeholder);
    }

    fn show_placeholder(&self) {
        let placeholder = gtk::Label::builder()
            .label("No saved networks")
            .css_classes(["balise-placeholder"])
            .build();
        self.list_box.append(&placeholder);
    }

    pub fn set_networks(&self, networks: Vec<SavedNetwork>) {
        while let Some(child) = self.list_box.first_child() {
            self.list_box.remove(&child);
        }

        if networks.is_empty() {
            self.show_placeholder();
            return;
        }

        let active: Vec<&SavedNetwork> = networks.iter().filter(|n| n.is_active).collect();
        let saved: Vec<&SavedNetwork> = networks.iter().filter(|n| !n.is_active).collect();

        if !active.is_empty() {
            let header = gtk::Label::builder()
                .label("CURRENTLY CONNECTED")
                .css_classes(["balise-section-header"])
                .halign(gtk::Align::Start)
                .build();
            self.list_box.append(&header);
            let card = super::section::section_card(&["connected"]);
            for n in active {
                card.append(&self.create_row(n));
            }
            self.list_box.append(&card);
        }

        if !saved.is_empty() {
            let header = gtk::Label::builder()
                .label("SAVED NETWORKS")
                .css_classes(["balise-section-header"])
                .halign(gtk::Align::Start)
                .build();
            self.list_box.append(&header);
            let card = super::section::section_card(&[]);
            for n in saved {
                card.append(&self.create_row(n));
            }
            self.list_box.append(&card);
        }
    }

    fn create_row(&self, network: &SavedNetwork) -> gtk::Box {
        let classes: Vec<&str> = if network.is_active {
            vec!["balise-saved-network-row", "active"]
        } else {
            vec!["balise-saved-network-row"]
        };

        let row = gtk::Box::builder()
            .orientation(Orientation::Horizontal)
            .spacing(6)
            .css_classes(classes)
            .focusable(true)
            .build();

        let row_focus = row.clone();
        let focus_in = gtk::EventControllerFocus::new();
        focus_in.connect_enter(move |_| row_focus.add_css_class("focused"));
        let row_unfocus = row.clone();
        let focus_out = gtk::EventControllerFocus::new();
        focus_out.connect_leave(move |_| row_unfocus.remove_css_class("focused"));
        row.add_controller(focus_in);
        row.add_controller(focus_out);

        let icon_classes = if network.is_active { "balise-icon-accent" } else { "balise-signal-icon" };
        let wifi_icon = gtk::Image::builder()
            .icon_name("network-wireless-symbolic")
            .pixel_size(16)
            .css_classes([icon_classes])
            .valign(gtk::Align::Center)
            .build();
        row.append(&wifi_icon);

        let info_box = gtk::Box::builder()
            .orientation(Orientation::Vertical)
            .spacing(0)
            .hexpand(true)
            .valign(gtk::Align::Center)
            .build();

        // Real SSID, with the connection.id shown alongside only when it
        // differs (renamed profile -- see the project plan's §6.2 fix in
        // dbus/network_manager.rs).
        let label = if network.id != network.ssid {
            format!("{} (id: {})", network.ssid, network.id)
        } else {
            network.ssid.clone()
        };
        let ssid = gtk::Label::builder()
            .label(&label)
            .css_classes(["balise-ssid"])
            .halign(gtk::Align::Start)
            .ellipsize(gtk::pango::EllipsizeMode::End)
            .build();
        info_box.append(&ssid);

        let status_text = if network.is_active {
            "Connected"
        } else if network.autoconnect {
            "Auto-connect enabled"
        } else {
            "Manual connect only"
        };
        let status = gtk::Label::builder()
            .label(status_text)
            .css_classes(["balise-status"])
            .halign(gtk::Align::Start)
            .build();
        if network.autoconnect && !network.is_active {
            status.add_css_class("balise-status-accent");
        }
        info_box.append(&status);
        row.append(&info_box);

        let autoconnect_switch = gtk::Switch::builder()
            .active(network.autoconnect)
            .css_classes(["balise-toggle-switch"])
            .halign(gtk::Align::Center)
            .valign(gtk::Align::Center)
            .build();
        row.append(&autoconnect_switch);

        // Gear -> detail page (replaces the red "Forget" button that
        // used to sit here; Forget now lives in the detail page).
        let gear_btn = gtk::Button::builder()
            .css_classes(["balise-button", "balise-gear-button", "flat"])
            .valign(gtk::Align::Center)
            .margin_start(4)
            .build();
        gear_btn.set_child(Some(&super::icon::icon_label(super::icon::GEAR)));
        row.append(&gear_btn);

        // Ignore the switch's initial `active(...)` construction as a
        // "user" toggle -- same 100ms settle window Orbit uses, since
        // GTK fires connect_state_notify once during construction too.
        let path_toggle = network.settings_path.clone();
        let on_toggle = self.on_autoconnect_toggle.clone();
        let is_user_action = Rc::new(RefCell::new(false));
        let is_user_action_clone = is_user_action.clone();
        glib::timeout_add_local(std::time::Duration::from_millis(100), move || {
            *is_user_action_clone.borrow_mut() = true;
            glib::ControlFlow::Break
        });
        autoconnect_switch.connect_state_notify(move |switch| {
            if *is_user_action.borrow() {
                if let Some(callback) = on_toggle.borrow().as_ref() {
                    callback(path_toggle.clone(), switch.is_active());
                }
            }
        });

        let ssid_detail = network.ssid.clone();
        let on_show_detail = self.on_show_detail.clone();
        gear_btn.connect_clicked(move |_| {
            if let Some(callback) = on_show_detail.borrow().as_ref() {
                callback(ssid_detail.clone());
            }
        });

        row
    }

    pub fn widget(&self) -> &gtk::Box {
        &self.container
    }

    pub fn set_on_autoconnect_toggle<F: Fn(String, bool) + 'static>(&self, callback: F) {
        *self.on_autoconnect_toggle.borrow_mut() = Some(Rc::new(callback));
    }

    /// Gear button -- receives the network's SSID, so the caller can
    /// resolve full details and open the shared detail page.
    pub fn set_on_show_detail<F: Fn(String) + 'static>(&self, callback: F) {
        *self.on_show_detail.borrow_mut() = Some(Rc::new(callback));
    }
}
