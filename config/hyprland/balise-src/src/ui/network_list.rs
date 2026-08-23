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

    /// Inline password entry (replaces the bottom overlay Balise used
    /// through Phase 1b): one revealer per secured row, keyed by SSID,
    /// with at most one open at a time.
    row_forms: Rc<RefCell<HashMap<String, gtk::Revealer>>>,
    expanded_ssid: Rc<RefCell<Option<String>>>,
    on_connect_password: Rc<RefCell<Option<Rc<dyn Fn(AccessPoint, String)>>>>,
    on_show_detail: Rc<RefCell<Option<Rc<dyn Fn(AccessPoint)>>>>,
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
            .vscrollbar_policy(gtk::PolicyType::External)
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

        let hidden_button = super::icon::icon_text_button(super::icon::EYE_SLASH, "Hidden", &["balise-button", "flat"]);

        let saved_button =
            super::icon::icon_text_button(super::icon::CLOCK_COUNTER_CLOCKWISE, "Saved", &["balise-button", "flat"]);

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
            row_forms: Rc::new(RefCell::new(HashMap::new())),
            expanded_ssid: Rc::new(RefCell::new(None)),
            on_connect_password: Rc::new(RefCell::new(None)),
            on_show_detail: Rc::new(RefCell::new(None)),
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
        // A password form is open: keep the fresh data, but do NOT
        // rebuild the rows. `render_networks` recreates every widget,
        // which would destroy the entry the user is typing into -- and
        // the WiFi tab re-polls every 5s while visible, so this fires
        // in the middle of typing a password almost every time.
        // Re-rendering resumes as soon as the form is closed (connect or
        // cancel), which ends with a refetch anyway.
        if self.expanded_ssid.borrow().is_some() {
            *self.networks.borrow_mut() = networks;
            return;
        }

        *self.networks.borrow_mut() = networks.clone();
        *self.connecting_ssid.borrow_mut() = None;
        *self.disconnecting_ssid.borrow_mut() = None;
        self.render_networks(&networks);
    }

    fn render_networks(&self, networks: &[AccessPoint]) {
        self.row_actions.borrow_mut().clear();
        self.row_forms.borrow_mut().clear();
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
            let card = super::section::section_card(&["connected"]);
            for network in connected {
                card.append(&self.create_network_row(network));
            }
            self.list_box.append(&card);
        }

        if !available.is_empty() {
            let header = gtk::Label::builder()
                .label("AVAILABLE NETWORKS")
                .css_classes(["balise-section-header"])
                .halign(gtk::Align::Start)
                .build();
            self.list_box.append(&header);
            let card = super::section::section_card(&[]);
            for network in available {
                card.append(&self.create_network_row(network));
            }
            self.list_box.append(&card);
        }
    }

    /// A row is now a VERTICAL box: the visible line on top, plus a
    /// collapsed password form underneath it (secured networks only).
    /// `.balise-network-row` sits on the outer box so the card divider
    /// and hover tint cover the whole block once it expands.
    fn create_network_row(&self, network: &AccessPoint) -> gtk::Box {
        let outer = gtk::Box::builder()
            .orientation(Orientation::Vertical)
            .css_classes(["balise-network-row"])
            .focusable(true)
            .build();

        let row = gtk::Box::builder().orientation(Orientation::Horizontal).spacing(12).build();

        let row_focus = outer.clone();
        let focus_in = gtk::EventControllerFocus::new();
        focus_in.connect_enter(move |_| row_focus.add_css_class("focused"));
        let row_unfocus = outer.clone();
        let focus_out = gtk::EventControllerFocus::new();
        focus_out.connect_leave(move |_| row_unfocus.remove_css_class("focused"));
        outer.add_controller(focus_in);
        outer.add_controller(focus_out);

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
        outer.append(&row);

        // Secured, unsaved networks get the inline password form. Open
        // ones connect straight away, and saved ones already have their
        // PSK in NetworkManager, so neither needs to prompt.
        if network.security.needs_password() && !network.is_saved && !network.is_connected {
            let revealer = self.build_password_form(network);
            self.row_forms.borrow_mut().insert(network.ssid.clone(), revealer.clone());
            outer.append(&revealer);
        }

        outer
    }

    /// The collapsed password form: entry + Cancel/Connect, revealed
    /// under its row when the row's Connect button is pressed.
    fn build_password_form(&self, network: &AccessPoint) -> gtk::Revealer {
        let form = gtk::Box::builder()
            .orientation(Orientation::Vertical)
            .spacing(8)
            .css_classes(["balise-inline-form"])
            .build();

        // PasswordEntry rather than a plain Entry: it ships GTK's own
        // reveal-password eye button, so there's nothing to build for
        // "let me check what I typed".
        let entry = gtk::PasswordEntry::builder().show_peek_icon(true).hexpand(true).build();
        entry.set_placeholder_text(Some("Password"));
        form.append(&entry);

        let buttons = gtk::Box::builder().orientation(Orientation::Horizontal).spacing(8).halign(gtk::Align::End).build();
        let cancel = gtk::Button::builder().label("Cancel").css_classes(["balise-button", "flat"]).build();
        let connect = gtk::Button::builder().label("Connect").css_classes(["balise-button", "primary", "flat"]).build();
        buttons.append(&cancel);
        buttons.append(&connect);
        form.append(&buttons);

        let revealer = gtk::Revealer::builder()
            .child(&form)
            .reveal_child(false)
            .transition_type(gtk::RevealerTransitionType::SlideDown)
            .transition_duration(200)
            .build();

        let submit = {
            let list = self.clone();
            let network = network.clone();
            let entry = entry.clone();
            move || {
                let password = entry.text().to_string();
                if password.is_empty() {
                    return;
                }
                list.collapse_forms();
                if let Some(cb) = list.on_connect_password.borrow().as_ref() {
                    cb(network.clone(), password);
                }
            }
        };

        let on_activate = submit.clone();
        entry.connect_activate(move |_| on_activate());
        let on_click = submit.clone();
        connect.connect_clicked(move |_| on_click());

        let list = self.clone();
        cancel.connect_clicked(move |_| list.collapse_forms());

        revealer
    }

    /// Closes every open password form and clears the expansion guard in
    /// `set_networks`, so polling can resume rebuilding rows.
    fn collapse_forms(&self) {
        for revealer in self.row_forms.borrow().values() {
            revealer.set_reveal_child(false);
        }
        *self.expanded_ssid.borrow_mut() = None;
    }

    /// Opens one row's form, closing any other. Returns false when this
    /// SSID has no form (open or already-saved network).
    fn expand_form(&self, ssid: &str) -> bool {
        let forms = self.row_forms.borrow();
        let Some(target) = forms.get(ssid) else { return false };

        for (key, revealer) in forms.iter() {
            revealer.set_reveal_child(key == ssid);
        }
        *self.expanded_ssid.borrow_mut() = Some(ssid.to_string());

        // Focus the entry so the password can be typed immediately --
        // the panel already holds keyboard focus (KeyboardMode::OnDemand
        // while shown, see window.rs).
        if let Some(form) = target.child() {
            if let Some(entry) = form.first_child() {
                entry.grab_focus();
            }
        }
        true
    }

    fn build_actions_box_content(&self, actions_box: &gtk::Box, network: &AccessPoint) {
        if network.security.needs_password() && !network.is_connected {
            let lock_icon = super::icon::icon_label(super::icon::LOCK_SIMPLE);
            lock_icon.add_css_class("balise-signal-icon");
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

            // Secured + unsaved: expand this row's inline password form
            // instead of firing a connect that would fail. Everything
            // else (open, already-saved, or disconnecting) acts
            // immediately. `expand_form` returning false means no form
            // was built for this row, so fall through to the direct
            // path rather than silently doing nothing.
            let network_clone = network.clone();
            let on_connect = self.on_connect.clone();
            let list = self.clone();
            action_btn.connect_clicked(move |_| {
                let needs_prompt =
                    network_clone.security.needs_password() && !network_clone.is_saved && !network_clone.is_connected;
                if needs_prompt && list.expand_form(&network_clone.ssid) {
                    return;
                }
                if let Some(callback) = on_connect.borrow().as_ref() {
                    callback(network_clone.clone());
                }
            });
            actions_box.append(&action_btn);
        }

        // Gear -> detail page. Replaces the destructive buttons that
        // used to live on rows: Forget/autoconnect now sit in there.
        let gear = super::icon::icon_label(super::icon::GEAR);
        let gear_btn = gtk::Button::builder().css_classes(["balise-button", "balise-gear-button", "flat"]).build();
        gear_btn.set_child(Some(&gear));
        gear_btn.set_valign(gtk::Align::Center);

        let network_detail = network.clone();
        let on_show_detail = self.on_show_detail.clone();
        gear_btn.connect_clicked(move |_| {
            if let Some(cb) = on_show_detail.borrow().as_ref() {
                cb(network_detail.clone());
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

    pub fn set_on_connect<F: Fn(AccessPoint) + 'static>(&self, callback: F) {
        *self.on_connect.borrow_mut() = Some(Rc::new(callback));
    }

    pub fn set_on_connect_hidden<F: Fn() + 'static>(&self, callback: F) {
        *self.on_connect_hidden.borrow_mut() = Some(Rc::new(callback));
    }

    pub fn set_on_show_saved<F: Fn() + 'static>(&self, callback: F) {
        *self.on_show_saved.borrow_mut() = Some(Rc::new(callback));
    }

    /// Fired by the inline form's Connect (or Enter in the entry).
    pub fn set_on_connect_password<F: Fn(AccessPoint, String) + 'static>(&self, callback: F) {
        *self.on_connect_password.borrow_mut() = Some(Rc::new(callback));
    }

    pub fn set_on_show_detail<F: Fn(AccessPoint) + 'static>(&self, callback: F) {
        *self.on_show_detail.borrow_mut() = Some(Rc::new(callback));
    }

    /// Last scan result for one SSID. The saved-networks overlay's gear
    /// only knows an SSID, and a saved network is not necessarily in
    /// range, so callers fall back to a synthetic entry when this is
    /// None.
    pub fn get_network(&self, ssid: &str) -> Option<AccessPoint> {
        self.networks.borrow().iter().find(|n| n.ssid == ssid).cloned()
    }
}
