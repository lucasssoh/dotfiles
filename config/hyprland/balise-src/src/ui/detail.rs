//! Endpoint detail page -- the 4th Stack page, shared by all three
//! tabs. Reached from a row's gear button, left via the header's back
//! button (see header.rs's detail mode).
//!
//! Not adapted from Orbit: it has no equivalent drill-in page. Its
//! closest thing is a Bluetooth-only "details" overlay plus a separate
//! forget-confirmation overlay, i.e. two more stacked revealers on a
//! panel that already carried five. This is a real Stack page instead,
//! so it gets the panel's full width/height, animates as navigation,
//! and works identically for WiFi/Bluetooth/Ethernet.
//!
//! It is also where every *destructive* and every *secondary* action
//! now lives (Forget, autoconnect, trust). The lists themselves keep
//! only their one primary action, which is what removed the red Forget
//! buttons that used to sit on every paired/saved row.

use gtk4::prelude::*;
use gtk4::{self as gtk, glib, Orientation};
use std::cell::RefCell;
use std::rc::Rc;

use super::device_list::DeviceAction;
use crate::dbus::{AccessPoint, BluetoothDevice, WifiDetails, WiredProfile};

/// What the page is currently showing. Carries the full backend record
/// rather than pre-formatted strings so the page can decide per field
/// whether there's anything worth rendering.
#[derive(Clone)]
pub enum DetailTarget {
    Wifi { ap: AccessPoint, details: WifiDetails },
    Bluetooth(BluetoothDevice),
    Ethernet(WiredProfile),
}

impl DetailTarget {
    /// Shown in the header next to the back arrow.
    pub fn title(&self) -> String {
        match self {
            DetailTarget::Wifi { ap, .. } => ap.ssid.clone(),
            DetailTarget::Bluetooth(d) => d.name.clone(),
            DetailTarget::Ethernet(p) => p.name.clone(),
        }
    }

    /// Which tab this endpoint came from -- the header's back button
    /// returns to it rather than to a fixed default.
    pub fn origin_tab(&self) -> &'static str {
        match self {
            DetailTarget::Wifi { .. } => "wifi",
            DetailTarget::Bluetooth(_) => "bluetooth",
            DetailTarget::Ethernet(_) => "ethernet",
        }
    }
}

#[derive(Clone)]
pub enum DetailAction {
    WifiDisconnect(String),
    WifiForget(String),
    WifiAutoconnect(String, bool),
    Bt(String, DeviceAction),
    BtTrust(String, bool),
    EthConnect(Box<WiredProfile>),
    EthDisconnect(String),
    EthAutoconnect(String, bool),
}

#[derive(Clone)]
pub struct DetailView {
    container: gtk::Box,
    content: gtk::Box,
    target: Rc<RefCell<Option<DetailTarget>>>,
    on_action: Rc<RefCell<Option<Rc<dyn Fn(DetailAction)>>>>,
}

impl DetailView {
    pub fn new() -> Self {
        let container = gtk::Box::builder().orientation(Orientation::Vertical).vexpand(true).hexpand(true).build();

        let scrolled = gtk::ScrolledWindow::builder()
            .vexpand(true)
            .hexpand(true)
            .hscrollbar_policy(gtk::PolicyType::Never)
            .css_classes(["balise-scrolled"])
            .build();

        let content = gtk::Box::builder().orientation(Orientation::Vertical).css_classes(["balise-detail"]).build();
        scrolled.set_child(Some(&content));
        container.append(&scrolled);

        Self { container, content, target: Rc::new(RefCell::new(None)), on_action: Rc::new(RefCell::new(None)) }
    }

    pub fn widget(&self) -> &gtk::Box {
        &self.container
    }

    pub fn set_on_action<F: Fn(DetailAction) + 'static>(&self, callback: F) {
        *self.on_action.borrow_mut() = Some(Rc::new(callback));
    }

    fn emit(&self, action: DetailAction) {
        if let Some(cb) = self.on_action.borrow().as_ref() {
            cb(action);
        }
    }

    pub fn set_target(&self, target: DetailTarget) {
        *self.target.borrow_mut() = Some(target.clone());
        while let Some(child) = self.content.first_child() {
            self.content.remove(&child);
        }

        match target {
            DetailTarget::Wifi { ap, details } => self.build_wifi(&ap, &details),
            DetailTarget::Bluetooth(device) => self.build_bluetooth(&device),
            DetailTarget::Ethernet(profile) => self.build_ethernet(&profile),
        }
    }

    // ---- per-type builders ----------------------------------------------

    fn build_wifi(&self, ap: &AccessPoint, details: &WifiDetails) {
        let status = if ap.is_connected {
            format!("Connected · {}% signal", ap.signal)
        } else if details.settings_path.is_empty() {
            format!("{}% signal · not saved", ap.signal)
        } else {
            format!("{}% signal · saved", ap.signal)
        };
        self.append_status_card(&status, ap.is_connected);

        self.append_section("NETWORK");
        let security = if ap.security.needs_password() { "Secured" } else { "Open" };
        let meta = vec![
            ("Security", security.to_string()),
            ("Signal", format!("{}%", ap.signal)),
            ("Link speed", details.speed.clone()),
            ("IPv4", details.ip4_address.clone()),
            ("Gateway", details.gateway.clone()),
            ("DNS", details.dns_servers.join(", ")),
            ("IPv6", details.ip6_address.clone()),
            ("MAC", details.mac_address.clone()),
        ];
        self.append_meta_card(&meta);

        // Autoconnect + Forget only mean anything for a stored profile.
        if !details.settings_path.is_empty() {
            self.append_section("OPTIONS");
            let path = details.settings_path.clone();
            self.append_toggle_card("Connect automatically", details.autoconnect, move |view, on| {
                view.emit(DetailAction::WifiAutoconnect(path.clone(), on));
            });
        }

        self.append_section("ACTIONS");
        if ap.is_connected {
            let ssid = ap.ssid.clone();
            self.append_button("Disconnect", &["balise-button", "flat"], move |view| {
                view.emit(DetailAction::WifiDisconnect(ssid.clone()));
            });
        }
        if !details.settings_path.is_empty() {
            let path = details.settings_path.clone();
            self.append_button("Forget this network", &["balise-button", "destructive", "flat"], move |view| {
                view.emit(DetailAction::WifiForget(path.clone()));
            });
        }
    }

    fn build_bluetooth(&self, device: &BluetoothDevice) {
        let status = if device.is_connected {
            match device.battery_percentage {
                Some(pct) => format!("Connected · {}%{}", pct, if device.is_charging { " (charging)" } else { "" }),
                None => "Connected".to_string(),
            }
        } else if device.is_paired {
            "Paired · not connected".to_string()
        } else {
            "Available · not paired".to_string()
        };
        self.append_status_card(&status, device.is_connected);

        self.append_section("DEVICE");
        let kind = match device.device_type {
            crate::dbus::DeviceType::Audio => "Audio",
            crate::dbus::DeviceType::Keyboard => "Keyboard",
            crate::dbus::DeviceType::Mouse => "Mouse",
            crate::dbus::DeviceType::Phone => "Phone",
            crate::dbus::DeviceType::Other => "Other",
        };
        let battery = match device.battery_percentage {
            Some(pct) => format!("{}%{}", pct, if device.is_charging { " (charging)" } else { "" }),
            None => String::new(),
        };
        // RSSI is only ever populated by an active scan, and reads 0 for
        // devices BlueZ merely remembers -- omit it rather than print a
        // misleading "0 dBm".
        let signal = if device.rssi != 0 { format!("{} dBm", device.rssi) } else { String::new() };
        let meta = vec![
            ("Type", kind.to_string()),
            ("Address", device.address.clone()),
            ("Battery", battery),
            ("Signal", signal),
            ("Paired", if device.is_paired { "Yes".into() } else { "No".to_string() }),
        ];
        self.append_meta_card(&meta);

        if device.is_paired {
            self.append_section("OPTIONS");
            let path = device.path.clone();
            self.append_toggle_card("Trusted device", device.is_trusted, move |view, on| {
                view.emit(DetailAction::BtTrust(path.clone(), on));
            });
        }

        self.append_section("ACTIONS");
        let path = device.path.clone();
        if device.is_connected {
            self.append_button("Disconnect", &["balise-button", "flat"], move |view| {
                view.emit(DetailAction::Bt(path.clone(), DeviceAction::Disconnect));
            });
        } else if device.is_paired {
            self.append_button("Connect", &["balise-button", "primary", "flat"], move |view| {
                view.emit(DetailAction::Bt(path.clone(), DeviceAction::Connect));
            });
        } else {
            self.append_button("Pair", &["balise-button", "primary", "flat"], move |view| {
                view.emit(DetailAction::Bt(path.clone(), DeviceAction::Pair));
            });
        }

        if device.is_paired {
            let path = device.path.clone();
            self.append_button("Forget this device", &["balise-button", "destructive", "flat"], move |view| {
                view.emit(DetailAction::Bt(path.clone(), DeviceAction::Forget));
            });
        }
    }

    fn build_ethernet(&self, profile: &WiredProfile) {
        let status = if profile.is_active {
            let speed = if profile.speed > 0 { format!(" · {} Mb/s", profile.speed) } else { String::new() };
            format!("Connected{}", speed)
        } else if profile.has_carrier {
            "Cable connected · not active".to_string()
        } else {
            "No cable".to_string()
        };
        self.append_status_card(&status, profile.is_active);

        self.append_section("INTERFACE");
        let speed = if profile.speed > 0 { format!("{} Mb/s", profile.speed) } else { String::new() };
        let meta = vec![
            ("Device", profile.device_name.clone()),
            ("Link speed", speed),
            ("IPv4", profile.ip4_address.clone()),
            ("Gateway", profile.gateway.clone()),
            ("DNS", profile.dns_servers.join(", ")),
            ("MAC", profile.mac_address.clone()),
        ];
        self.append_meta_card(&meta);

        if !profile.connection_path.is_empty() {
            self.append_section("OPTIONS");
            let path = profile.connection_path.clone();
            self.append_toggle_card("Connect automatically", profile.autoconnect, move |view, on| {
                view.emit(DetailAction::EthAutoconnect(path.clone(), on));
            });
        }

        self.append_section("ACTIONS");
        if profile.is_active {
            let device_path = profile.device_path.clone();
            self.append_button("Disconnect", &["balise-button", "flat"], move |view| {
                view.emit(DetailAction::EthDisconnect(device_path.clone()));
            });
        } else if profile.has_carrier {
            let p = profile.clone();
            self.append_button("Connect", &["balise-button", "primary", "flat"], move |view| {
                view.emit(DetailAction::EthConnect(Box::new(p.clone())));
            });
        }
    }

    // ---- building blocks -------------------------------------------------

    fn append_status_card(&self, status: &str, connected: bool) {
        let card = super::section::section_card(if connected { &["connected"] } else { &[] });
        let row = gtk::Box::builder().orientation(Orientation::Horizontal).css_classes(["balise-network-row"]).build();
        let label = gtk::Label::builder().label(status).css_classes(["balise-ssid"]).halign(gtk::Align::Start).hexpand(true).build();
        label.set_ellipsize(gtk::pango::EllipsizeMode::End);
        row.append(&label);
        card.append(&row);
        self.content.append(&card);
    }

    fn append_section(&self, title: &str) {
        let header = gtk::Label::builder().label(title).css_classes(["balise-section-header"]).halign(gtk::Align::Start).build();
        self.content.append(&header);
    }

    /// One card of label/value pairs. Empty values are dropped entirely
    /// (a disconnected network has no IP, an unpaired device no
    /// battery) rather than rendered as a blank row.
    fn append_meta_card(&self, entries: &[(&str, String)]) {
        let visible: Vec<&(&str, String)> = entries.iter().filter(|(_, v)| !v.is_empty()).collect();
        if visible.is_empty() {
            return;
        }

        let card = super::section::section_card(&[]);
        for (label, value) in visible {
            let row = gtk::Box::builder().orientation(Orientation::Horizontal).spacing(12).css_classes(["balise-network-row"]).build();
            let key = gtk::Label::builder().label(*label).css_classes(["balise-meta-label"]).halign(gtk::Align::Start).build();
            let val = gtk::Label::builder().label(value).css_classes(["balise-meta-value"]).halign(gtk::Align::End).hexpand(true).build();
            val.set_ellipsize(gtk::pango::EllipsizeMode::End);
            val.set_selectable(true);
            row.append(&key);
            row.append(&val);
            card.append(&row);
        }
        self.content.append(&card);
    }

    fn append_toggle_card<F: Fn(&DetailView, bool) + 'static>(&self, label: &str, active: bool, callback: F) {
        let card = super::section::section_card(&[]);
        let row = gtk::Box::builder().orientation(Orientation::Horizontal).spacing(12).css_classes(["balise-network-row"]).build();

        let text = gtk::Label::builder().label(label).css_classes(["balise-ssid"]).halign(gtk::Align::Start).hexpand(true).build();
        let toggle = gtk::Switch::builder().active(active).css_classes(["balise-toggle-switch"]).valign(gtk::Align::Center).build();
        row.append(&text);
        row.append(&toggle);
        card.append(&row);
        self.content.append(&card);

        // GTK fires state-notify once while the switch is being built
        // with `active(...)`, which would immediately write the value
        // back to NetworkManager/BlueZ as if the user had flipped it --
        // same 100ms settle window saved_list.rs/wired_list.rs use.
        let view = self.clone();
        let is_user_action = Rc::new(RefCell::new(false));
        let settle = is_user_action.clone();
        glib::timeout_add_local(std::time::Duration::from_millis(100), move || {
            *settle.borrow_mut() = true;
            glib::ControlFlow::Break
        });
        toggle.connect_state_notify(move |sw| {
            if *is_user_action.borrow() {
                callback(&view, sw.is_active());
            }
        });
    }

    fn append_button<F: Fn(&DetailView) + 'static>(&self, label: &str, classes: &[&str], callback: F) {
        let button = gtk::Button::builder().label(label).css_classes(classes.to_vec()).hexpand(true).build();
        button.add_css_class("balise-detail-button");
        let view = self.clone();
        button.connect_clicked(move |_| callback(&view));
        self.content.append(&button);
    }
}
