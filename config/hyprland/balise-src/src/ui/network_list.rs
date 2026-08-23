//! Scanned access-point list: search, signal bars, connect/disconnect,
//! footer (Scan/Hidden/Saved). Adapted from
//! orbit-vendor/src/ui/network_list.rs, dropping the "Details" button
//! (network details view is not in Phase 1b's scope).

use gtk4::prelude::*;
use gtk4::{self as gtk, Orientation};
use std::cell::RefCell;
use std::collections::HashMap;
use std::rc::Rc;

use crate::dbus::{AccessPoint, SecurityType};

#[derive(Clone)]
pub struct NetworkList {
    container: gtk::Box,
    list_box: gtk::Box,
    scan_button: gtk::Button,
    search_entry: gtk::SearchEntry,
    networks: Rc<RefCell<Vec<AccessPoint>>>,
    row_actions: Rc<RefCell<HashMap<String, gtk::Box>>>,
    on_connect: Rc<RefCell<Option<Rc<dyn Fn(AccessPoint)>>>>,
    on_connect_hidden: Rc<RefCell<Option<Rc<dyn Fn()>>>>,
    on_show_saved: Rc<RefCell<Option<Rc<dyn Fn()>>>>,
    connecting_ssid: Rc<RefCell<Option<String>>>,
    disconnecting_ssid: Rc<RefCell<Option<String>>>,
}

impl NetworkList {
    pub fn new() -> Self {
        let container = gtk::Box::builder()
            .orientation(Orientation::Vertical)
            .vexpand(true)
            .hexpand(true)
            .build();

        let search_box = gtk::Box::builder()
            .orientation(Orientation::Horizontal)
            .css_classes(["balise-search-container"])
            .margin_start(8)
            .margin_end(8)
            .margin_top(4)
            .margin_bottom(8)
            .build();

        let list_box = gtk::Box::builder()
            .orientation(Orientation::Vertical)
            .css_classes(["balise-list"])
            .focusable(true)
            .build();

        let search_entry = gtk::SearchEntry::builder()
            .placeholder_text("Search networks...")
            .hexpand(true)
            .css_classes(["balise-search-entry"])
            .can_focus(true)
            .build();

        // Escape: clear the search if non-empty, else hide the whole
        // panel (mirrors Orbit's exact behavior).
        let esc_handler = gtk::EventControllerKey::new();
        let search_clone = search_entry.clone();
        let list_box_focus = list_box.clone();
        let root_anchor = container.clone();
        esc_handler.connect_key_pressed(move |_, key, _, _| {
            if key == gtk4::gdk::Key::Escape {
                if !search_clone.text().is_empty() {
                    search_clone.set_text("");
                    list_box_focus.grab_focus();
                    return gtk4::glib::Propagation::Stop;
                } else if let Some(root) = root_anchor.root() {
                    if let Some(win) = root.downcast_ref::<gtk::Window>() {
                        win.set_visible(false);
                    }
                    return gtk4::glib::Propagation::Stop;
                }
            }
            gtk4::glib::Propagation::Proceed
        });
        search_entry.add_controller(esc_handler);

        search_box.append(&search_entry);
        container.append(&search_box);

        let scrolled = gtk::ScrolledWindow::builder()
            .vexpand(true)
            .hexpand(true)
            .hscrollbar_policy(gtk::PolicyType::Never)
            .min_content_height(280)
            .css_classes(["balise-scrolled"])
            .build();
        scrolled.set_child(Some(&list_box));
        container.append(&scrolled);

        let footer = gtk::Box::builder()
            .css_classes(["balise-footer"])
            .margin_top(8)
            .spacing(8)
            .build();

        let scan_button = super::icon::icon_text_button(super::icon::ARROWS_CLOCKWISE, "Scan", &["balise-button", "primary", "flat"]);
        scan_button.set_hexpand(true);
        scan_button.set_tooltip_text(Some("Scan for Networks"));

        let hidden_button = super::icon::icon_text_button(super::icon::EYE_SLASH, "Hidden", &["balise-button", "flat"]);
        hidden_button.set_tooltip_text(Some("Hidden Network"));

        let saved_button =
            super::icon::icon_text_button(super::icon::CLOCK_COUNTER_CLOCKWISE, "Saved", &["balise-button", "flat"]);
        saved_button.set_tooltip_text(Some("Saved Networks"));

        footer.append(&scan_button);
        footer.append(&hidden_button);
        footer.append(&saved_button);
        container.append(&footer);

        let list = Self {
            container,
            list_box,
            scan_button,
            search_entry: search_entry.clone(),
            networks: Rc::new(RefCell::new(Vec::new())),
            row_actions: Rc::new(RefCell::new(HashMap::new())),
            on_connect: Rc::new(RefCell::new(None)),
            on_connect_hidden: Rc::new(RefCell::new(None)),
            on_show_saved: Rc::new(RefCell::new(None)),
            connecting_ssid: Rc::new(RefCell::new(None)),
            disconnecting_ssid: Rc::new(RefCell::new(None)),
        };

        let list_clone = list.clone();
        search_entry.connect_search_changed(move |_| {
            let networks = list_clone.networks.borrow().clone();
            list_clone.render_networks(&networks);
        });

        let on_connect_hidden_cb = list.on_connect_hidden.clone();
        hidden_button.connect_clicked(move |_| {
            if let Some(cb) = on_connect_hidden_cb.borrow().as_ref() {
                cb();
            }
        });

        let on_show_saved_cb = list.on_show_saved.clone();
        saved_button.connect_clicked(move |_| {
            if let Some(cb) = on_show_saved_cb.borrow().as_ref() {
                cb();
            }
        });

        list.show_loading();
        list
    }

    fn show_loading(&self) {
        let placeholder = gtk::Label::builder()
            .label("Loading networks...")
            .css_classes(["balise-placeholder"])
            .build();
        self.list_box.append(&placeholder);
    }

    fn show_placeholder(&self) {
        let placeholder = gtk::Label::builder()
            .label("Click 'Scan' to find networks")
            .css_classes(["balise-placeholder"])
            .build();
        self.list_box.append(&placeholder);
    }

    fn signal_bar_count(strength: u8) -> u8 {
        match strength {
            0..=24 => 1,
            25..=49 => 2,
            50..=74 => 3,
            _ => 4,
        }
    }

    fn build_signal_bars(strength: u8, is_connected: bool) -> gtk::Box {
        let active_bars = Self::signal_bar_count(strength);
        let heights = [4, 8, 12, 16];

        let container = gtk::Box::builder()
            .orientation(Orientation::Horizontal)
            .spacing(2)
            .valign(gtk::Align::End)
            .halign(gtk::Align::Center)
            .build();

        for (i, &h) in heights.iter().enumerate() {
            let bar_num = (i + 1) as u8;
            let active = bar_num <= active_bars;

            let bar = gtk::Box::builder()
                .width_request(3)
                .height_request(h)
                .valign(gtk::Align::End)
                .build();

            if active {
                bar.add_css_class(if is_connected {
                    "balise-signal-bar-active-accent"
                } else {
                    "balise-signal-bar-active"
                });
            } else {
                bar.add_css_class("balise-signal-bar-inactive");
            }

            container.append(&bar);
        }

        container
    }

    pub fn set_connecting_ssid(&self, ssid: Option<String>) {
        let old_ssid = self.connecting_ssid.borrow().clone();
        *self.connecting_ssid.borrow_mut() = ssid.clone();
        if let Some(ref s) = ssid {
            self.update_single_row_actions(s);
        }
        if let Some(ref s) = old_ssid {
            self.update_single_row_actions(s);
        }
    }

    pub fn set_disconnecting_ssid(&self, ssid: Option<String>) {
        let old_ssid = self.disconnecting_ssid.borrow().clone();
        *self.disconnecting_ssid.borrow_mut() = ssid.clone();
        if let Some(ref s) = ssid {
            self.update_single_row_actions(s);
        }
        if let Some(ref s) = old_ssid {
            self.update_single_row_actions(s);
        }
    }

    fn update_single_row_actions(&self, ssid: &str) {
        let networks = self.networks.borrow();
        if let Some(network) = networks.iter().find(|n| n.ssid == ssid) {
            let actions_map = self.row_actions.borrow();
            if let Some(actions_box) = actions_map.get(ssid) {
                while let Some(child) = actions_box.first_child() {
                    actions_box.remove(&child);
                }
                self.build_actions_box_content(actions_box, network);
            }
        }
    }

    pub fn set_networks(&self, networks: Vec<AccessPoint>) {
        *self.networks.borrow_mut() = networks.clone();
        *self.connecting_ssid.borrow_mut() = None;
        *self.disconnecting_ssid.borrow_mut() = None;
        self.render_networks(&networks);
    }

    fn render_networks(&self, networks: &[AccessPoint]) {
        self.row_actions.borrow_mut().clear();
        while let Some(child) = self.list_box.first_child() {
            self.list_box.remove(&child);
        }

        if networks.is_empty() {
            self.show_placeholder();
            return;
        }

        let query = self.search_entry.text().to_string().to_lowercase();
        let filtered: Vec<&AccessPoint> = if query.is_empty() {
            networks.iter().collect()
        } else {
            networks
                .iter()
                .filter(|n| n.ssid.to_lowercase().contains(&query))
                .collect()
        };

        if filtered.is_empty() && !query.is_empty() {
            let no_match = gtk::Label::builder()
                .label(&format!("No networks matching '{}'", query))
                .css_classes(["balise-placeholder"])
                .build();
            self.list_box.append(&no_match);
            return;
        }

        let connected: Vec<&&AccessPoint> = filtered.iter().filter(|n| n.is_connected).collect();
        let available: Vec<&&AccessPoint> = filtered.iter().filter(|n| !n.is_connected).collect();

        if !connected.is_empty() {
            let header = gtk::Label::builder()
                .label("ACTIVE CONNECTION")
                .css_classes(["balise-section-header"])
                .halign(gtk::Align::Start)
                .build();
            self.list_box.append(&header);
            for network in connected {
                self.list_box.append(&self.create_network_row(network));
            }
        }

        if !available.is_empty() {
            let header = gtk::Label::builder()
                .label("AVAILABLE NETWORKS")
                .css_classes(["balise-section-header"])
                .halign(gtk::Align::Start)
                .build();
            self.list_box.append(&header);
            for network in available {
                self.list_box.append(&self.create_network_row(network));
            }
        }
    }

    fn create_network_row(&self, network: &AccessPoint) -> gtk::Box {
        let row = gtk::Box::builder()
            .orientation(Orientation::Horizontal)
            .spacing(12)
            .css_classes(["balise-network-row"])
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

        if network.is_connected {
            let icon_container = gtk::Box::builder()
                .css_classes(["balise-icon-container"])
                .halign(gtk::Align::Center)
                .valign(gtk::Align::Center)
                .build();
            icon_container.append(&Self::build_signal_bars(network.signal, true));
            row.append(&icon_container);
        } else {
            let bars = Self::build_signal_bars(network.signal, false);
            bars.set_valign(gtk::Align::Center);
            bars.add_css_class("balise-signal-bars-pad");
            row.append(&bars);
        }

        let info_box = gtk::Box::builder()
            .orientation(Orientation::Vertical)
            .spacing(2)
            .hexpand(true)
            .valign(gtk::Align::Center)
            .build();

        let ssid = gtk::Label::builder()
            .label(&network.ssid)
            .css_classes(["balise-ssid"])
            .halign(gtk::Align::Start)
            .ellipsize(gtk::pango::EllipsizeMode::End)
            .build();
        info_box.append(&ssid);

        let status_text = if network.is_connected {
            format!("Connected · {}%", network.signal)
        } else {
            let sec = if network.security != SecurityType::None { "Secure" } else { "Open" };
            let saved = if network.is_saved { " · Saved" } else { "" };
            format!("{}% Signal · {}{}", network.signal, sec, saved)
        };
        let status = gtk::Label::builder()
            .label(&status_text)
            .css_classes(["balise-status"])
            .halign(gtk::Align::Start)
            .build();
        info_box.append(&status);
        row.append(&info_box);

        let actions_box = gtk::Box::builder().orientation(Orientation::Horizontal).spacing(8).build();
        self.build_actions_box_content(&actions_box, network);
        self.row_actions.borrow_mut().insert(network.ssid.clone(), actions_box.clone());
        row.append(&actions_box);
        row
    }

    fn build_actions_box_content(&self, actions_box: &gtk::Box, network: &AccessPoint) {
        if network.security.needs_password() && !network.is_connected {
            let lock_icon = super::icon::icon_label(super::icon::LOCK_SIMPLE);
            lock_icon.add_css_class("balise-signal-icon");
            lock_icon.set_tooltip_text(Some("Secure Network"));
            lock_icon.set_valign(gtk::Align::Center);
            actions_box.append(&lock_icon);
        }

        let is_connecting = self.connecting_ssid.borrow().as_deref() == Some(&network.ssid);
        let is_disconnecting = self.disconnecting_ssid.borrow().as_deref() == Some(&network.ssid);
        let any_connecting = self.connecting_ssid.borrow().is_some();
        let any_disconnecting = self.disconnecting_ssid.borrow().is_some();

        if is_connecting || is_disconnecting {
            let working_box = gtk::Box::builder()
                .orientation(Orientation::Horizontal)
                .spacing(8)
                .css_classes(["balise-working-indicator"])
                .build();
            let spinner = gtk::Spinner::builder().spinning(true).build();
            spinner.start();
            let label = gtk::Label::builder()
                .label(if is_connecting { "Connecting..." } else { "Disconnecting..." })
                .css_classes(["balise-status"])
                .build();
            working_box.append(&spinner);
            working_box.append(&label);
            actions_box.append(&working_box);
        } else {
            let action_label = if network.is_connected { "Disconnect" } else { "Connect" };
            let classes: Vec<&str> = if network.is_connected {
                vec!["balise-button", "flat"]
            } else {
                vec!["balise-button", "primary", "flat"]
            };
            let action_btn = gtk::Button::builder()
                .label(action_label)
                .css_classes(classes)
                .sensitive(
                    !(any_connecting && !network.is_connected) && !(any_disconnecting && network.is_connected),
                )
                .build();

            let network_clone = network.clone();
            let on_connect = self.on_connect.clone();
            action_btn.connect_clicked(move |_| {
                if let Some(callback) = on_connect.borrow().as_ref() {
                    callback(network_clone.clone());
                }
            });
            actions_box.append(&action_btn);
        }
    }

    pub fn widget(&self) -> &gtk::Box {
        &self.container
    }

    pub fn scan_button(&self) -> &gtk::Button {
        &self.scan_button
    }

    pub fn set_on_connect<F: Fn(AccessPoint) + 'static>(&self, callback: F) {
        *self.on_connect.borrow_mut() = Some(Rc::new(callback));
    }

    pub fn set_on_connect_hidden<F: Fn() + 'static>(&self, callback: F) {
        *self.on_connect_hidden.borrow_mut() = Some(Rc::new(callback));
    }

    pub fn set_on_show_saved<F: Fn() + 'static>(&self, callback: F) {
        *self.on_show_saved.borrow_mut() = Some(Rc::new(callback));
    }
}
