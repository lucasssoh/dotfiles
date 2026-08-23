//! Bluetooth device list (Phase 3). Adapted from
//! orbit-vendor/src/ui/device_list.rs, simplified: one generic Phosphor
//! glyph for every device (Orbit differentiates audio/keyboard/mouse/
//! phone via GTK system icons; the row's own name text already conveys
//! that), no battery-level icon (just the raw percentage), and no
//! details/forget-confirm overlays -- each row carries a gear button
//! that opens the shared detail page (ui/detail.rs) instead, which is
//! where Forget and the trust toggle now live.

use gtk4::{self as gtk, prelude::*, Orientation};
use std::cell::RefCell;
use std::collections::HashMap;
use std::rc::Rc;

use crate::dbus::BluetoothDevice;

#[derive(Clone, PartialEq)]
pub enum DeviceAction {
    Connect,
    Disconnect,
    Pair,
    Forget,
}

#[derive(Clone)]
pub struct DeviceList {
    container: gtk::Box,
    list_box: gtk::Box,
    scan_button: gtk::Button,
    devices: Rc<RefCell<Vec<BluetoothDevice>>>,
    row_actions: Rc<RefCell<HashMap<String, gtk::Box>>>,
    on_action: Rc<RefCell<Option<Rc<dyn Fn(String, DeviceAction)>>>>,
    on_show_detail: Rc<RefCell<Option<Rc<dyn Fn(String)>>>>,
    action_path: Rc<RefCell<Option<String>>>,
    action_type: Rc<RefCell<Option<DeviceAction>>>,
}

impl DeviceList {
    pub fn new() -> Self {
        let container = gtk::Box::builder().orientation(Orientation::Vertical).vexpand(true).hexpand(true).build();

        let scrolled = gtk::ScrolledWindow::builder()
            .vexpand(true)
            .hexpand(true)
            .hscrollbar_policy(gtk::PolicyType::Never)
            .vscrollbar_policy(gtk::PolicyType::External)
            .min_content_height(280)
            .css_classes(["balise-scrolled"])
            .build();

        let list_box = gtk::Box::builder().orientation(Orientation::Vertical).css_classes(["balise-list"]).build();
        scrolled.set_child(Some(&list_box));
        container.append(&scrolled);

        let footer = gtk::Box::builder().css_classes(["balise-footer"]).margin_top(8).build();
        let scan_button =
            super::icon::icon_text_button(super::icon::ARROWS_CLOCKWISE, "Scan for Devices", &["balise-button", "primary", "flat"]);
        scan_button.set_hexpand(true);
        footer.append(&scan_button);
        container.append(&footer);

        let list = Self {
            container,
            list_box,
            scan_button,
            devices: Rc::new(RefCell::new(Vec::new())),
            row_actions: Rc::new(RefCell::new(HashMap::new())),
            on_action: Rc::new(RefCell::new(None)),
            on_show_detail: Rc::new(RefCell::new(None)),
            action_path: Rc::new(RefCell::new(None)),
            action_type: Rc::new(RefCell::new(None)),
        };
        list.show_loading();
        list
    }

    fn show_loading(&self) {
        let placeholder = gtk::Label::builder().label("Loading devices...").css_classes(["balise-placeholder"]).build();
        self.list_box.append(&placeholder);
    }

    fn show_placeholder(&self) {
        let placeholder = gtk::Label::builder().label("Click 'Scan' to find devices").css_classes(["balise-placeholder"]).build();
        self.list_box.append(&placeholder);
    }

    pub fn show_scanning(&self) {
        while let Some(child) = self.list_box.first_child() {
            self.list_box.remove(&child);
        }
        let scanning = gtk::Label::builder().label("Scanning for devices...").css_classes(["balise-placeholder"]).build();
        self.list_box.append(&scanning);
    }

    pub fn set_action_state(&self, path: Option<String>, action: Option<DeviceAction>) {
        let old_path = self.action_path.borrow().clone();
        *self.action_path.borrow_mut() = path.clone();
        *self.action_type.borrow_mut() = action;

        if let Some(ref p) = path {
            self.update_single_row_actions(p);
        }
        if let Some(ref p) = old_path {
            self.update_single_row_actions(p);
        }
    }

    fn update_single_row_actions(&self, path: &str) {
        let devices = self.devices.borrow();
        if let Some(device) = devices.iter().find(|d| d.path == path) {
            let actions_map = self.row_actions.borrow();
            if let Some(actions_box) = actions_map.get(path) {
                while let Some(child) = actions_box.first_child() {
                    actions_box.remove(&child);
                }
                self.build_actions_box_content(actions_box, device);
            }
        }
    }

    pub fn set_devices(&self, devices: Vec<BluetoothDevice>) {
        *self.devices.borrow_mut() = devices.clone();
        *self.action_path.borrow_mut() = None;
        *self.action_type.borrow_mut() = None;
        self.render_devices(&devices);
    }

    fn render_devices(&self, devices: &[BluetoothDevice]) {
        self.row_actions.borrow_mut().clear();
        while let Some(child) = self.list_box.first_child() {
            self.list_box.remove(&child);
        }

        if devices.is_empty() {
            self.show_placeholder();
            return;
        }

        let connected: Vec<&BluetoothDevice> = devices.iter().filter(|d| d.is_connected).collect();
        let paired: Vec<&BluetoothDevice> = devices.iter().filter(|d| d.is_paired && !d.is_connected).collect();
        let available: Vec<&BluetoothDevice> = devices.iter().filter(|d| !d.is_paired).collect();

        if !connected.is_empty() {
            let header = gtk::Label::builder().label("CONNECTED").css_classes(["balise-section-header"]).halign(gtk::Align::Start).build();
            self.list_box.append(&header);
            let card = super::section::section_card(&["connected"]);
            for d in connected {
                card.append(&self.create_device_row(d));
            }
            self.list_box.append(&card);
        }
        if !paired.is_empty() {
            let header = gtk::Label::builder().label("PAIRED").css_classes(["balise-section-header"]).halign(gtk::Align::Start).build();
            self.list_box.append(&header);
            let card = super::section::section_card(&[]);
            for d in paired {
                card.append(&self.create_device_row(d));
            }
            self.list_box.append(&card);
        }
        if !available.is_empty() {
            let header = gtk::Label::builder().label("AVAILABLE").css_classes(["balise-section-header"]).halign(gtk::Align::Start).build();
            self.list_box.append(&header);
            let card = super::section::section_card(&[]);
            for d in available {
                card.append(&self.create_device_row(d));
            }
            self.list_box.append(&card);
        }
    }

    fn create_device_row(&self, device: &BluetoothDevice) -> gtk::Box {
        let classes: Vec<&str> = if device.is_connected { vec!["balise-network-row", "connected"] } else { vec!["balise-network-row"] };
        let row = gtk::Box::builder().orientation(Orientation::Horizontal).spacing(12).css_classes(classes).focusable(true).build();

        let row_focus = row.clone();
        let focus_in = gtk::EventControllerFocus::new();
        focus_in.connect_enter(move |_| row_focus.add_css_class("focused"));
        let row_unfocus = row.clone();
        let focus_out = gtk::EventControllerFocus::new();
        focus_out.connect_leave(move |_| row_unfocus.remove_css_class("focused"));
        row.add_controller(focus_in);
        row.add_controller(focus_out);

        let icon = super::icon::icon_label(super::icon::BLUETOOTH);
        icon.add_css_class(if device.is_connected { "balise-icon-accent" } else { "balise-signal-icon" });
        icon.set_valign(gtk::Align::Center);
        row.append(&icon);

        let info_box = gtk::Box::builder().orientation(Orientation::Vertical).spacing(2).hexpand(true).valign(gtk::Align::Center).build();

        let name = gtk::Label::builder().label(&device.name).css_classes(["balise-ssid"]).halign(gtk::Align::Start).build();
        name.set_ellipsize(gtk::pango::EllipsizeMode::End);
        info_box.append(&name);

        let status_text = if device.is_connected {
            "Connected".to_string()
        } else if device.is_paired {
            "Paired".to_string()
        } else {
            "Available".to_string()
        };
        let status_text = match device.battery_percentage {
            Some(pct) => format!("{} · {}%{}", status_text, pct, if device.is_charging { " (charging)" } else { "" }),
            None => status_text,
        };
        let status = gtk::Label::builder()
            .label(&status_text)
            .css_classes(["balise-status"])
            .halign(gtk::Align::Start)
            // Ellipsized like the name above it: without this the row's
            // natural width includes the whole status string, and a long
            // one widens the entire panel (measured: it was pinning the
            // window 23px past its width_request).
            .ellipsize(gtk::pango::EllipsizeMode::End)
            .build();
        info_box.append(&status);
        row.append(&info_box);

        let actions_box = gtk::Box::builder().orientation(Orientation::Horizontal).spacing(8).build();
        self.build_actions_box_content(&actions_box, device);
        self.row_actions.borrow_mut().insert(device.path.clone(), actions_box.clone());
        row.append(&actions_box);
        row
    }

    fn build_actions_box_content(&self, actions_box: &gtk::Box, device: &BluetoothDevice) {
        let is_busy = self.action_path.borrow().as_deref() == Some(&device.path);

        if is_busy {
            let spinner = gtk::Spinner::builder().spinning(true).build();
            spinner.start();
            let text = match self.action_type.borrow().as_ref() {
                Some(DeviceAction::Connect) => "Connecting...",
                Some(DeviceAction::Disconnect) => "Disconnecting...",
                Some(DeviceAction::Pair) => "Pairing...",
                Some(DeviceAction::Forget) => "Removing...",
                None => "Working...",
            };
            let label = gtk::Label::builder().label(text).css_classes(["balise-status"]).build();
            let working_box = gtk::Box::builder().orientation(Orientation::Horizontal).spacing(8).css_classes(["balise-working-indicator"]).build();
            working_box.append(&spinner);
            working_box.append(&label);
            actions_box.append(&working_box);
            return;
        }

        let (action_label, action) = if device.is_connected {
            ("Disconnect", DeviceAction::Disconnect)
        } else if device.is_paired {
            ("Connect", DeviceAction::Connect)
        } else {
            ("Pair", DeviceAction::Pair)
        };

        let action_btn = gtk::Button::builder()
            .label(action_label)
            .css_classes(if device.is_paired { vec!["balise-button", "primary", "flat"] } else { vec!["balise-button", "flat"] })
            .build();
        let path = device.path.clone();
        let on_action = self.on_action.clone();
        let action_clone = action.clone();
        action_btn.connect_clicked(move |_| {
            if let Some(cb) = on_action.borrow().as_ref() {
                cb(path.clone(), action_clone.clone());
            }
        });
        actions_box.append(&action_btn);

        // Gear -> detail page. This replaces the red "Forget" button
        // that used to sit on every paired row (asked for: no
        // destructive buttons in the list). Forget, plus the trust
        // toggle and the full device metadata, now live in there.
        let gear_btn = gtk::Button::builder().css_classes(["balise-button", "balise-gear-button", "flat"]).build();
        gear_btn.set_child(Some(&super::icon::icon_label(super::icon::GEAR)));
        gear_btn.set_valign(gtk::Align::Center);

        let path = device.path.clone();
        let on_show_detail = self.on_show_detail.clone();
        gear_btn.connect_clicked(move |_| {
            if let Some(cb) = on_show_detail.borrow().as_ref() {
                cb(path.clone());
            }
        });
        actions_box.append(&gear_btn);
    }

    pub fn widget(&self) -> &gtk::Box {
        &self.container
    }

    pub fn scan_button(&self) -> &gtk::Button {
        &self.scan_button
    }

    pub fn set_on_action<F: Fn(String, DeviceAction) + 'static>(&self, callback: F) {
        *self.on_action.borrow_mut() = Some(Rc::new(callback));
    }

    /// Gear button -- receives the device's object path.
    pub fn set_on_show_detail<F: Fn(String) + 'static>(&self, callback: F) {
        *self.on_show_detail.borrow_mut() = Some(Rc::new(callback));
    }

    pub fn get_device_name(&self, path: &str) -> Option<String> {
        self.devices.borrow().iter().find(|d| d.path == path).map(|d| d.name.clone())
    }

    /// Full record for the detail page -- served straight from the last
    /// scan result, so opening details needs no extra D-Bus round trip
    /// (BlueZ's GetManagedObjects already returned every field).
    pub fn get_device(&self, path: &str) -> Option<BluetoothDevice> {
        self.devices.borrow().iter().find(|d| d.path == path).cloned()
    }
}
