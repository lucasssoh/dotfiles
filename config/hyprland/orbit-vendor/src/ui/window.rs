use gtk4::{ApplicationWindow, Application, prelude::*, Overlay};
use gtk4::{self as gtk, Orientation};
use gtk4_layer_shell::{LayerShell, Layer, KeyboardMode, Edge};
use std::cell::{Cell, RefCell};
use std::rc::Rc;

use crate::config::Config;
use crate::theme::Theme;
use super::header::Header;
use super::network_list::NetworkList;
use super::device_list::DeviceList;
use super::saved_networks_list::SavedNetworksList;
use super::vpn_list::VpnList;
use crate::dbus::network_manager::{NetworkDetails, WiredProfile};

pub struct OrbitWindow {
    window: ApplicationWindow,
    root_revealer: gtk::Revealer,
    config: Rc<RefCell<Config>>,
    header: Header,
    network_list: NetworkList,
    saved_networks_list: SavedNetworksList,
    device_list: DeviceList,
    vpn_list: VpnList,
    stack: gtk::Stack,
    details_revealer: gtk::Revealer,
    details_box: gtk::Box,
    details_content: gtk::Box,
    password_revealer: gtk::Revealer,
    password_box: gtk::Box,
    password_entry: gtk::PasswordEntry,
    password_label: gtk::Label,
    password_error_label: gtk::Label,
    password_connect_btn: gtk::Button,
    password_callback: Rc<RefCell<Option<Rc<dyn Fn(Option<String>)>>>>,
    details_callback: Rc<RefCell<Option<Rc<dyn Fn(String, bool)>>>>, // (path, trust)
    forget_callback: Rc<RefCell<Option<Rc<dyn Fn(String)>>>>,
    hidden_revealer: gtk::Revealer,
    hidden_ssid_entry: gtk::Entry,
    hidden_password_entry: gtk::PasswordEntry,
    hidden_connect_btn: gtk::Button,
    hidden_callback: Rc<RefCell<Option<Rc<dyn Fn(Option<(String, String)>)>>>>,
    saved_revealer: gtk::Revealer,
    error_revealer: gtk::Revealer,
    error_box: gtk::Box,
    error_label: gtk::Label,
    bt_agent_revealer: gtk::Revealer,
    bt_agent_box: gtk::Box,
    bt_agent_label: gtk::Label,
    bt_agent_entry: gtk::Entry,
    bt_agent_confirm_btn: gtk::Button,
    bt_agent_cancel_btn: gtk::Button,
    bt_pin_callback: Rc<RefCell<Option<async_channel::Sender<String>>>>,
    bt_passkey_callback: Rc<RefCell<Option<async_channel::Sender<u32>>>>,
    bt_confirm_callback: Rc<RefCell<Option<async_channel::Sender<bool>>>>,
    wired_revealer: gtk::Revealer,
    wired_list_box: gtk::Box,
    wired_connect_callback: Rc<RefCell<Option<Rc<dyn Fn(String, String)>>>>,
    wired_disconnect_callback: Rc<RefCell<Option<Rc<dyn Fn(String)>>>>,
    wired_autoconnect_callback: Rc<RefCell<Option<Rc<dyn Fn(String, bool)>>>>,
    theme: Rc<RefCell<Theme>>,
    css_provider: gtk4::CssProvider,
    user_css_provider: gtk4::CssProvider,
    is_animating: Rc<Cell<bool>>,
}

impl Clone for OrbitWindow {
    fn clone(&self) -> Self {
        Self {
            window: self.window.clone(),
            root_revealer: self.root_revealer.clone(),
            config: self.config.clone(),
            header: self.header.clone(),
            network_list: self.network_list.clone(),
            saved_networks_list: self.saved_networks_list.clone(),
            device_list: self.device_list.clone(),
            vpn_list: self.vpn_list.clone(),
            stack: self.stack.clone(),
            details_revealer: self.details_revealer.clone(),
            details_box: self.details_box.clone(),
            details_content: self.details_content.clone(),
            password_revealer: self.password_revealer.clone(),
            password_box: self.password_box.clone(),
            password_entry: self.password_entry.clone(),
            password_label: self.password_label.clone(),
            password_error_label: self.password_error_label.clone(),
            password_connect_btn: self.password_connect_btn.clone(),
            password_callback: self.password_callback.clone(),
            details_callback: self.details_callback.clone(),
            forget_callback: self.forget_callback.clone(),
            hidden_revealer: self.hidden_revealer.clone(),
            hidden_ssid_entry: self.hidden_ssid_entry.clone(),
            hidden_password_entry: self.hidden_password_entry.clone(),
            hidden_connect_btn: self.hidden_connect_btn.clone(),
            hidden_callback: self.hidden_callback.clone(),
            saved_revealer: self.saved_revealer.clone(),
            error_revealer: self.error_revealer.clone(),
            error_box: self.error_box.clone(),
            error_label: self.error_label.clone(),
            bt_agent_revealer: self.bt_agent_revealer.clone(),
            bt_agent_box: self.bt_agent_box.clone(),
            bt_agent_label: self.bt_agent_label.clone(),
            bt_agent_entry: self.bt_agent_entry.clone(),
            bt_agent_confirm_btn: self.bt_agent_confirm_btn.clone(),
            bt_agent_cancel_btn: self.bt_agent_cancel_btn.clone(),
            bt_pin_callback: self.bt_pin_callback.clone(),
            bt_passkey_callback: self.bt_passkey_callback.clone(),
            bt_confirm_callback: self.bt_confirm_callback.clone(),
            wired_revealer: self.wired_revealer.clone(),
            wired_list_box: self.wired_list_box.clone(),
            wired_connect_callback: self.wired_connect_callback.clone(),
            wired_disconnect_callback: self.wired_disconnect_callback.clone(),
            wired_autoconnect_callback: self.wired_autoconnect_callback.clone(),
            theme: self.theme.clone(),
            css_provider: self.css_provider.clone(),
            user_css_provider: self.user_css_provider.clone(),
            is_animating: self.is_animating.clone(),
        }
    }
}

impl OrbitWindow {
    pub fn new(app: &Application, config: Config, theme: Rc<RefCell<Theme>>) -> Self {
        println!("Loaded config: window_transition = '{}'", config.window_transition);
        let window = ApplicationWindow::builder()
            .application(app)
            .default_width(420)
            .default_height(500)
            .resizable(false)
            .decorated(false)
            .build();
        
        window.init_layer_shell();
        window.set_namespace("orbit");
        window.set_layer(Layer::Overlay);
        window.set_keyboard_mode(KeyboardMode::None);
        window.set_exclusive_zone(0);
        window.set_default_size(420, 500);
        // No "background" class: that's GTK's own class for painting an
        // opaque themed rectangle behind everything, which doesn't follow
        // this window's rounded corners (see orbit/style.css's own
        // background-color: transparent override, kept as a defensive
        // belt-and-braces in case some other GTK/theme path re-adds an
        // opaque fill here). Leaving it off means main_box's own
        // .orbit-panel rounded fill is the only thing ever painted.

        let css_provider = gtk4::CssProvider::new();
        let user_css_provider = gtk4::CssProvider::new();
        
        let display = gtk4::gdk::Display::default().expect("Failed to get default display");
        gtk4::style_context_add_provider_for_display(
            &display,
            &css_provider,
            gtk4::STYLE_PROVIDER_PRIORITY_USER,
        );

        gtk4::style_context_add_provider_for_display(
            &display,
            &user_css_provider,
            gtk4::STYLE_PROVIDER_PRIORITY_USER,
        );

        let config = Rc::new(RefCell::new(config));

        let main_box = gtk::Box::builder()
            .orientation(Orientation::Vertical)
            .css_classes(["orbit-panel"])
            .vexpand(true)
            .hexpand(true)
            .overflow(gtk::Overflow::Hidden)
            .build();
        
        let header = Header::new();
        main_box.append(header.widget());
        
        let stack = gtk::Stack::builder()
            .vexpand(true)
            .hexpand(true)
            .transition_type(parse_stack_transition(&config.borrow().stack_transition))
            .transition_duration(config.borrow().stack_transition_duration)
            .build();
        
        let network_list = NetworkList::new();
        let saved_networks_list = SavedNetworksList::new();
        let device_list = DeviceList::new();
        let vpn_list = VpnList::new();
        
        stack.add_named(network_list.widget(), Some("wifi"));
        stack.add_named(device_list.widget(), Some("bluetooth"));
        stack.add_named(vpn_list.widget(), Some("vpn"));
        stack.set_visible_child_name("wifi");
        stack.set_size_request(400, 350);
        
        main_box.append(&stack);
        
        let overlay = Overlay::new();
        overlay.set_child(Some(&main_box));
        
        let details_box = gtk::Box::builder()
            .orientation(Orientation::Vertical)
            .css_classes(["orbit-details-overlay"])
            .spacing(8)
            .margin_start(16)
            .margin_end(16)
            .margin_top(16)
            .margin_bottom(16)
            .build();
        
        let details_header_row = gtk::Box::builder()
            .orientation(Orientation::Horizontal)
            .spacing(12)
            .build();
        
        let details_title = gtk::Label::builder()
            .label("Network Details")
            .css_classes(["orbit-detail-label"])
            .halign(gtk::Align::Start)
            .hexpand(true)
            .build();
        
        let details_close_icon_btn = gtk::Button::builder()
            .icon_name("window-close-symbolic")
            .css_classes(["orbit-button", "flat"])
            .build();
        
        details_header_row.append(&details_title);
        details_header_row.append(&details_close_icon_btn);
        
        let details_content = gtk::Box::builder()
            .orientation(Orientation::Vertical)
            .spacing(4)
            .build();
        
        details_box.append(&details_header_row);
        details_box.append(&details_content);
        
        let details_revealer = gtk::Revealer::builder()
            .child(&details_box)
            .reveal_child(false)
            .transition_type(gtk::RevealerTransitionType::SlideUp)
            .transition_duration(250)
            .valign(gtk::Align::End)
            .can_target(true)
            .build();
        
        let details_revealer_clone = details_revealer.clone();
        details_close_icon_btn.connect_clicked(move |_| {
            details_revealer_clone.set_reveal_child(false);
        });
        
        overlay.add_overlay(&details_revealer);
        
        let password_box = gtk::Box::builder()
            .orientation(Orientation::Vertical)
            .spacing(12)
            .css_classes(["orbit-password-overlay"])
            .margin_start(16)
            .margin_end(16)
            .margin_top(16)
            .margin_bottom(16)
            .build();
        
        let password_label = gtk::Label::builder()
            .label("Enter password:")
            .css_classes(["orbit-detail-label"])
            .halign(gtk::Align::Start)
            .build();
        
        let password_entry = gtk::PasswordEntry::builder()
            .placeholder_text("Password")
            .hexpand(true)
            .build();
        
        let password_error_label = gtk::Label::builder()
            .label("")
            .css_classes(["orbit-error-text-small"])
            .halign(gtk::Align::Start)
            .visible(false)
            .build();
        
        let password_btn_row = gtk::Box::builder()
            .orientation(Orientation::Horizontal)
            .spacing(8)
            .halign(gtk::Align::End)
            .build();
        
        let password_cancel_btn = gtk::Button::builder()
            .label("Cancel")
            .css_classes(["orbit-button", "flat"])
            .build();
        
        let password_connect_btn = gtk::Button::builder()
            .label("Connect")
            .css_classes(["orbit-button", "primary", "flat"])
            .build();
        
        password_btn_row.append(&password_cancel_btn);
        password_btn_row.append(&password_connect_btn);
        
        password_box.append(&password_label);
        password_box.append(&password_entry);
        password_box.append(&password_error_label);
        password_box.append(&password_btn_row);
        
        let password_revealer = gtk::Revealer::builder()
            .child(&password_box)
            .reveal_child(false)
            .transition_type(gtk::RevealerTransitionType::SlideUp)
            .transition_duration(250)
            .valign(gtk::Align::End)
            .can_target(true)
            .build();
        
        let password_revealer_clone = password_revealer.clone();
        let password_entry_clone = password_entry.clone();
        password_cancel_btn.connect_clicked(move |_| {
            password_revealer_clone.set_reveal_child(false);
            password_entry_clone.set_text("");
        });
        
        overlay.add_overlay(&password_revealer);

        let hidden_box = gtk::Box::builder()
            .orientation(Orientation::Vertical)
            .spacing(12)
            .css_classes(["orbit-password-overlay"])
            .margin_start(16)
            .margin_end(16)
            .margin_top(16)
            .margin_bottom(16)
            .build();
        
        let hidden_label = gtk::Label::builder()
            .label("Connect to Hidden Network")
            .css_classes(["orbit-detail-label"])
            .halign(gtk::Align::Start)
            .build();
        
        let hidden_ssid_entry = gtk::Entry::builder()
            .placeholder_text("Network Name (SSID)")
            .hexpand(true)
            .build();
        
        let hidden_pass_entry = gtk::PasswordEntry::builder()
            .placeholder_text("Password (Optional)")
            .hexpand(true)
            .build();
        
        let hidden_btn_row = gtk::Box::builder()
            .orientation(Orientation::Horizontal)
            .spacing(8)
            .halign(gtk::Align::End)
            .build();
        
        let hidden_cancel_btn = gtk::Button::builder()
            .label("Cancel")
            .css_classes(["orbit-button", "flat"])
            .build();
        
        let hidden_connect_btn = gtk::Button::builder()
            .label("Connect")
            .css_classes(["orbit-button", "primary", "flat"])
            .build();
        
        hidden_btn_row.append(&hidden_cancel_btn);
        hidden_btn_row.append(&hidden_connect_btn);
        
        hidden_box.append(&hidden_label);
        hidden_box.append(&hidden_ssid_entry);
        hidden_box.append(&hidden_pass_entry);
        hidden_box.append(&hidden_btn_row);
        
        let hidden_revealer = gtk::Revealer::builder()
            .child(&hidden_box)
            .reveal_child(false)
            .transition_type(gtk::RevealerTransitionType::SlideUp)
            .transition_duration(250)
            .valign(gtk::Align::End)
            .can_target(true)
            .build();
        
        let hidden_revealer_clone = hidden_revealer.clone();
        hidden_cancel_btn.connect_clicked(move |_| {
            hidden_revealer_clone.set_reveal_child(false);
        });
        
        overlay.add_overlay(&hidden_revealer);

        let error_box = gtk::Box::builder()
            .orientation(Orientation::Vertical)
            .spacing(8)
            .css_classes(["orbit-error-overlay"])
            .margin_start(16)
            .margin_end(16)
            .margin_top(16)
            .margin_bottom(16)
            .build();
        
        let error_header = gtk::Box::builder()
            .orientation(Orientation::Horizontal)
            .spacing(8)
            .build();
            
        let error_icon = gtk::Image::builder()
            .icon_name("dialog-error-symbolic")
            .pixel_size(16)
            .valign(gtk::Align::Center)
            .build();
            
        let error_title = gtk::Label::builder()
            .label("Error")
            .css_classes(["orbit-error-title"])
            .halign(gtk::Align::Start)
            .hexpand(true)
            .build();
            
        let error_close_btn = gtk::Button::builder()
            .icon_name("window-close-symbolic")
            .css_classes(["orbit-button", "flat"])
            .build();
            
        error_header.append(&error_icon);
        error_header.append(&error_title);
        error_header.append(&error_close_btn);
        
        let error_label = gtk::Label::builder()
            .label("")
            .css_classes(["orbit-error-text"])
            .halign(gtk::Align::Start)
            .wrap(true)
            .build();
            
        error_box.append(&error_header);
        error_box.append(&error_label);
        
        let error_revealer = gtk::Revealer::builder()
            .child(&error_box)
            .reveal_child(false)
            .transition_type(gtk::RevealerTransitionType::SlideUp)
            .transition_duration(250)
            .valign(gtk::Align::End)
            .can_target(true)
            .build();
            
        let error_revealer_clone = error_revealer.clone();
        error_close_btn.connect_clicked(move |_| {
            error_revealer_clone.set_reveal_child(false);
        });
        
        overlay.add_overlay(&error_revealer);

        // Saved Networks Overlay
        let saved_box = gtk::Box::builder()
            .orientation(Orientation::Vertical)
            .css_classes(["orbit-password-overlay"])
            .spacing(8)
            .width_request(380)
            .build();
        
        let saved_header_row = gtk::Box::builder()
            .orientation(Orientation::Horizontal)
            .spacing(12)
            .build();
        
        let saved_title = gtk::Label::builder()
            .label("Saved Networks")
            .css_classes(["orbit-detail-label"])
            .halign(gtk::Align::Start)
            .hexpand(true)
            .build();
        
        let saved_close_icon_btn = gtk::Button::builder()
            .icon_name("window-close-symbolic")
            .css_classes(["orbit-button", "flat"])
            .build();
        
        saved_header_row.append(&saved_title);
        saved_header_row.append(&saved_close_icon_btn);
        
        saved_box.append(&saved_header_row);
        
        let saved_list_widget = saved_networks_list.widget().clone();
        saved_list_widget.set_visible(true);
        saved_list_widget.set_vexpand(true);
        saved_list_widget.set_hexpand(true);
        saved_box.append(&saved_list_widget);
        
        let saved_revealer = gtk::Revealer::builder()
            .child(&saved_box)
            .reveal_child(false)
            .transition_type(gtk::RevealerTransitionType::SlideUp)
            .transition_duration(250)
            .valign(gtk::Align::End)
            .can_target(true)
            .build();
        
        let saved_revealer_clone = saved_revealer.clone();
        saved_close_icon_btn.connect_clicked(move |_| {
            saved_revealer_clone.set_reveal_child(false);
        });
        
        overlay.add_overlay(&saved_revealer);

        // Bluetooth Agent Overlay
        let bt_agent_box = gtk::Box::builder()
            .orientation(Orientation::Vertical)
            .spacing(12)
            .css_classes(["orbit-password-overlay"])
            .margin_start(16)
            .margin_end(16)
            .margin_top(16)
            .margin_bottom(16)
            .build();
        
        let bt_agent_label = gtk::Label::builder()
            .label("Bluetooth Pairing Request")
            .css_classes(["orbit-detail-label"])
            .halign(gtk::Align::Start)
            .wrap(true)
            .build();
        
        let bt_agent_entry = gtk::Entry::builder()
            .placeholder_text("PIN / Passkey")
            .hexpand(true)
            .visible(false)
            .build();
        
        let bt_agent_btn_row = gtk::Box::builder()
            .orientation(Orientation::Horizontal)
            .spacing(8)
            .halign(gtk::Align::End)
            .build();
        
        let bt_agent_cancel_btn = gtk::Button::builder()
            .label("Cancel")
            .css_classes(["orbit-button", "flat"])
            .build();
        
        let bt_agent_confirm_btn = gtk::Button::builder()
            .label("Confirm")
            .css_classes(["orbit-button", "primary", "flat"])
            .build();
        
        bt_agent_btn_row.append(&bt_agent_cancel_btn);
        bt_agent_btn_row.append(&bt_agent_confirm_btn);
        
        bt_agent_box.append(&bt_agent_label);
        bt_agent_box.append(&bt_agent_entry);
        bt_agent_box.append(&bt_agent_btn_row);
        
        let bt_agent_revealer = gtk::Revealer::builder()
            .child(&bt_agent_box)
            .reveal_child(false)
            .transition_type(gtk::RevealerTransitionType::SlideUp)
            .transition_duration(250)
            .valign(gtk::Align::End)
            .can_target(true)
            .build();
        
        overlay.add_overlay(&bt_agent_revealer);
        
        let wired_box = gtk::Box::builder()
            .orientation(Orientation::Vertical)
            .css_classes(["orbit-wired-overlay"])
            .spacing(8)
            .margin_start(16)
            .margin_end(16)
            .margin_top(16)
            .margin_bottom(16)
            .build();
        
        let wired_header_row = gtk::Box::builder()
            .orientation(Orientation::Horizontal)
            .spacing(12)
            .build();
        
        let wired_title = gtk::Label::builder()
            .label("Wired Connections")
            .css_classes(["orbit-detail-label"])
            .halign(gtk::Align::Start)
            .hexpand(true)
            .build();
        
        let wired_close_btn = gtk::Button::builder()
            .icon_name("window-close-symbolic")
            .css_classes(["orbit-button", "flat"])
            .build();
        
        wired_header_row.append(&wired_title);
        wired_header_row.append(&wired_close_btn);
        
        wired_box.append(&wired_header_row);
        
        let wired_list_box = gtk::Box::builder()
            .orientation(Orientation::Vertical)
            .spacing(8)
            .vexpand(true)
            .build();
        
        wired_box.append(&wired_list_box);
        
        let wired_revealer = gtk::Revealer::builder()
            .child(&wired_box)
            .reveal_child(false)
            .transition_type(gtk::RevealerTransitionType::SlideUp)
            .transition_duration(250)
            .valign(gtk::Align::End)
            .can_target(true)
            .build();
        
        overlay.add_overlay(&wired_revealer);
        
        let wired_revealer_close = wired_revealer.clone();
        wired_close_btn.connect_clicked(move |_| {
            wired_revealer_close.set_reveal_child(false);
        });
        
        let root_revealer = gtk::Revealer::builder()
            .transition_type(parse_revealer_transition(&config.borrow().window_transition))
            .transition_duration(config.borrow().window_transition_duration)
            .child(&overlay)
            .valign(gtk::Align::Start)
            .build();
        
        overlay.set_valign(gtk::Align::Start);
        main_box.set_valign(gtk::Align::Start);
        
        window.set_child(Some(&root_revealer));
        
        let password_callback: Rc<RefCell<Option<Rc<dyn Fn(Option<String>)>>>> = Rc::new(RefCell::new(None));
        let details_callback: Rc<RefCell<Option<Rc<dyn Fn(String, bool)>>>> = Rc::new(RefCell::new(None));
        let forget_callback: Rc<RefCell<Option<Rc<dyn Fn(String)>>>> = Rc::new(RefCell::new(None));
        let hidden_callback: Rc<RefCell<Option<Rc<dyn Fn(Option<(String, String)>)>>>> = Rc::new(RefCell::new(None));
        
        let bt_pin_callback: Rc<RefCell<Option<async_channel::Sender<String>>>> = Rc::new(RefCell::new(None));
        let bt_passkey_callback: Rc<RefCell<Option<async_channel::Sender<u32>>>> = Rc::new(RefCell::new(None));
        let bt_confirm_callback: Rc<RefCell<Option<async_channel::Sender<bool>>>> = Rc::new(RefCell::new(None));

        let wired_connect_callback: Rc<RefCell<Option<Rc<dyn Fn(String, String)>>>> = Rc::new(RefCell::new(None));
        let wired_disconnect_callback: Rc<RefCell<Option<Rc<dyn Fn(String)>>>> = Rc::new(RefCell::new(None));
        let wired_autoconnect_callback: Rc<RefCell<Option<Rc<dyn Fn(String, bool)>>>> = Rc::new(RefCell::new(None));

        let bt_pin_cb = bt_pin_callback.clone();
        let bt_pass_cb = bt_passkey_callback.clone();
        let bt_conf_cb = bt_confirm_callback.clone();
        let bt_rev = bt_agent_revealer.clone();
        let bt_ent = bt_agent_entry.clone();
        
        bt_agent_confirm_btn.connect_clicked(move |_| {
            if let Some(tx) = bt_pin_cb.borrow_mut().take() {
                let _ = tx.send_blocking(bt_ent.text().to_string());
            } else if let Some(tx) = bt_pass_cb.borrow_mut().take() {
                if let Ok(val) = bt_ent.text().to_string().parse::<u32>() {
                    let _ = tx.send_blocking(val);
                }
            } else if let Some(tx) = bt_conf_cb.borrow_mut().take() {
                let _ = tx.send_blocking(true);
            }
            bt_rev.set_reveal_child(false);
        });

        let bt_pin_cancel = bt_pin_callback.clone();
        let bt_pass_cancel = bt_passkey_callback.clone();
        let bt_conf_cancel = bt_confirm_callback.clone();
        let bt_rev_cancel = bt_agent_revealer.clone();
        bt_agent_cancel_btn.connect_clicked(move |_| {
            let _ = bt_pin_cancel.borrow_mut().take();
            let _ = bt_pass_cancel.borrow_mut().take();
            if let Some(tx) = bt_conf_cancel.borrow_mut().take() {
                let _ = tx.send_blocking(false);
            }
            bt_rev_cancel.set_reveal_child(false);
        });

        let win = Self {
            window: window.clone(),
            root_revealer,
            config,
            header,
            network_list,
            saved_networks_list,
            device_list,
            vpn_list,
            stack,
            details_revealer,
            details_box,
            details_content,
            password_revealer,
            password_box,
            password_entry,
            password_label,
            password_error_label,
            password_connect_btn,
            password_callback,
            details_callback,
            forget_callback,
            hidden_revealer,
            hidden_ssid_entry,
            hidden_password_entry: hidden_pass_entry.clone(),
            hidden_connect_btn: hidden_connect_btn.clone(),
            hidden_callback,
            saved_revealer,
            error_revealer,
            error_box,
            error_label,
            bt_agent_revealer,
            bt_agent_box,
            bt_agent_label,
            bt_agent_entry,
            bt_agent_confirm_btn,
            bt_agent_cancel_btn,
            bt_pin_callback,
            bt_passkey_callback,
            bt_confirm_callback,
            wired_revealer,
            wired_list_box,
            wired_connect_callback,
            wired_disconnect_callback,
            wired_autoconnect_callback,
            theme,
            css_provider,
            user_css_provider,
            is_animating: Rc::new(Cell::new(false)),
        };

        let key_controller = gtk::EventControllerKey::new();
        let win_clone = win.clone();
        key_controller.connect_key_pressed(move |_, key, _, _| {
            if key == gtk4::gdk::Key::Escape {
                if win_clone.details_revealer.reveals_child() {
                    win_clone.details_revealer.set_reveal_child(false);
                    return gtk4::glib::Propagation::Stop;
                }
                if win_clone.password_revealer.reveals_child() {
                    win_clone.hide_password_dialog();
                    return gtk4::glib::Propagation::Stop;
                }
                if win_clone.hidden_revealer.reveals_child() {
                    win_clone.hidden_revealer.set_reveal_child(false);
                    return gtk4::glib::Propagation::Stop;
                }
                if win_clone.saved_revealer.reveals_child() {
                    win_clone.saved_revealer.set_reveal_child(false);
                    return gtk4::glib::Propagation::Stop;
                }
                if win_clone.bt_agent_revealer.reveals_child() {
                    win_clone.bt_agent_revealer.set_reveal_child(false);
                    let _ = win_clone.bt_pin_callback.borrow_mut().take();
                    let _ = win_clone.bt_passkey_callback.borrow_mut().take();
                    if let Some(tx) = win_clone.bt_confirm_callback.borrow_mut().take() {
                        let _ = tx.send_blocking(false);
                    }
                    return gtk4::glib::Propagation::Stop;
                }
                if win_clone.error_revealer.reveals_child() {
                    win_clone.error_revealer.set_reveal_child(false);
                    return gtk4::glib::Propagation::Stop;
                }
                if win_clone.wired_revealer.reveals_child() {
                    win_clone.wired_revealer.set_reveal_child(false);
                    return gtk4::glib::Propagation::Stop;
                }

                win_clone.hide();
                gtk4::glib::Propagation::Stop
            } else if key == gtk4::gdk::Key::Down || key == gtk4::gdk::Key::Tab {
                win_clone.window.child_focus(gtk::DirectionType::TabForward);
                gtk4::glib::Propagation::Stop
            } else if key == gtk4::gdk::Key::Up || key == gtk4::gdk::Key::ISO_Left_Tab {
                win_clone.window.child_focus(gtk::DirectionType::TabBackward);
                gtk4::glib::Propagation::Stop
            } else {
                gtk4::glib::Propagation::Proceed
            }
        });
        window.add_controller(key_controller);
        
        win.apply_position();
        win.apply_theme();
        win
    }
    
    pub fn apply_theme(&self) {
        let css = self.theme.borrow().generate_css();
        self.css_provider.load_from_data(&css);

        let user_css_path = Theme::style_css_path();
        if let Some(ref path) = user_css_path {
            if path.exists() {
                self.user_css_provider.load_from_path(path);
            } else {
                self.user_css_provider.load_from_data("");
            }
        } else {
            self.user_css_provider.load_from_data("");
        }
    }
    
    pub fn show(&self) {
        if self.is_animating.get() {
            return;
        }
        self.is_animating.set(true);

        self.window.set_visible(true);
        self.window.present();
        self.window.set_keyboard_mode(KeyboardMode::OnDemand);

        let rev = self.root_revealer.clone();
        let anim = self.is_animating.clone();
        let duration = self.config.borrow().window_transition_duration;

        gtk::glib::idle_add_local_once(move || {
            rev.set_reveal_child(true);
            gtk::glib::timeout_add_local(
                std::time::Duration::from_millis(duration.into()),
                move || {
                    anim.set(false);
                    gtk::glib::ControlFlow::Break
                },
            );
        });
    }
    
    pub fn hide(&self) {
        if self.is_animating.get() {
            return;
        }
        self.is_animating.set(true);

        self.root_revealer.set_reveal_child(false);

        let window = self.window.clone();
        let anim = self.is_animating.clone();
        let duration = self.config.borrow().window_transition_duration;

        gtk::glib::timeout_add_local(
            std::time::Duration::from_millis(duration.into()),
            move || {
                window.set_visible(false);
                window.set_keyboard_mode(KeyboardMode::None);
                anim.set(false);
                gtk::glib::ControlFlow::Break
            },
        );
    }
    
    pub fn network_list(&self) -> &NetworkList {
        &self.network_list
    }
    
    pub fn device_list(&self) -> &DeviceList {
        &self.device_list
    }

    pub fn vpn_list(&self) -> &VpnList {
        &self.vpn_list
    }

    pub fn saved_networks_list(&self) -> &SavedNetworksList {
        &self.saved_networks_list
    }
    
    pub fn header(&self) -> &Header {
        &self.header
    }
    
    pub fn stack(&self) -> &gtk::Stack {
        &self.stack
    }

    pub fn set_position(&self, pos_str: &str) {
        self.config.borrow_mut().position = pos_str.to_string();
        self.apply_position();
    }
    
    pub fn apply_position(&self) {
        let config = self.config.borrow();
        let pos = &config.position;
        
        self.window.set_margin(Edge::Top, config.margin_top);
        self.window.set_margin(Edge::Bottom, config.margin_bottom);
        self.window.set_margin(Edge::Left, config.margin_left);
        self.window.set_margin(Edge::Right, config.margin_right);
        
        self.window.set_anchor(Edge::Top, false);
        self.window.set_anchor(Edge::Bottom, false);
        self.window.set_anchor(Edge::Left, false);
        self.window.set_anchor(Edge::Right, false);
        
        match pos.as_str() {
            "top-left" => {
                self.window.set_anchor(Edge::Top, true);
                self.window.set_anchor(Edge::Left, true);
            }
            "top-center" => {
                self.window.set_anchor(Edge::Top, true);
            }
            "top-right" => {
                self.window.set_anchor(Edge::Top, true);
                self.window.set_anchor(Edge::Right, true);
            }
            "center-left" => {
                self.window.set_anchor(Edge::Left, true);
            }
            "center" => {
                // No anchors = centered
            }
            "center-right" => {
                self.window.set_anchor(Edge::Right, true);
            }
            "bottom-left" => {
                self.window.set_anchor(Edge::Bottom, true);
                self.window.set_anchor(Edge::Left, true);
            }
            "bottom-center" => {
                self.window.set_anchor(Edge::Bottom, true);
            }
            "bottom-right" => {
                self.window.set_anchor(Edge::Bottom, true);
                self.window.set_anchor(Edge::Right, true);
            }
            _ => {
                self.window.set_anchor(Edge::Top, true);
                self.window.set_anchor(Edge::Right, true);
            }
        }
    }
    
    pub fn reload_config(&self) {
        let mut config = self.config.borrow_mut();
        *config = Config::load();
        
        println!("Reloaded config: window_transition = '{}'", config.window_transition);
        
        self.root_revealer.set_transition_type(parse_revealer_transition(&config.window_transition));
        self.root_revealer.set_transition_duration(config.window_transition_duration);
        
        self.stack.set_transition_type(parse_stack_transition(&config.stack_transition));
        self.stack.set_transition_duration(config.stack_transition_duration);
        
        drop(config);
        self.apply_position();
    }
    
    pub fn show_password_dialog<F: Fn(Option<String>) + 'static>(&self, ssid: &str, callback: F) {
        self.password_label.set_label(&format!("Enter password for {}:", ssid));
        self.password_entry.set_text("");
        self.password_error_label.set_visible(false);
        *self.password_callback.borrow_mut() = Some(Rc::new(callback));
        
        let callback_clone = self.password_callback.clone();
        let entry_clone = self.password_entry.clone();
        let rev_clone = self.password_revealer.clone();
        self.password_connect_btn.connect_clicked(move |_| {
            if let Some(cb) = callback_clone.borrow().as_ref() {
                cb(Some(entry_clone.text().to_string()));
            }
            rev_clone.set_reveal_child(false);
        });
        
        self.details_revealer.set_reveal_child(false);
        self.saved_revealer.set_reveal_child(false);
        self.hidden_revealer.set_reveal_child(false);
        self.password_revealer.set_reveal_child(true);
        self.password_entry.grab_focus();
    }
    
    pub fn hide_password_dialog(&self) {
        self.password_revealer.set_reveal_child(false);
        self.password_entry.set_text("");
    }
    
    pub fn show_hidden_dialog<F: Fn(Option<(String, String)>) + 'static>(&self, callback: F) {
        self.hidden_ssid_entry.set_text("");
        self.hidden_password_entry.set_text("");
        *self.hidden_callback.borrow_mut() = Some(Rc::new(callback));
        
        let callback_clone = self.hidden_callback.clone();
        let ssid_clone = self.hidden_ssid_entry.clone();
        let pass_clone = self.hidden_password_entry.clone();
        let rev_clone = self.hidden_revealer.clone();
        
        self.hidden_connect_btn.connect_clicked(move |_| {
            if let Some(cb) = callback_clone.borrow().as_ref() {
                cb(Some((ssid_clone.text().to_string(), pass_clone.text().to_string())));
            }
            rev_clone.set_reveal_child(false);
        });
        
        self.details_revealer.set_reveal_child(false);
        self.saved_revealer.set_reveal_child(false);
        self.password_revealer.set_reveal_child(false);
        self.hidden_revealer.set_reveal_child(true);
        self.hidden_ssid_entry.grab_focus();
    }
    
    pub fn show_error(&self, msg: &str) {
        self.error_label.set_label(sanitize_error_message(msg).as_str());
        self.error_revealer.set_reveal_child(true);
        
        let rev = self.error_revealer.clone();
        gtk::glib::timeout_add_local(std::time::Duration::from_secs(5), move || {
            rev.set_reveal_child(false);
            gtk::glib::ControlFlow::Break
        });
    }
    
    pub fn show_network_details(&self, details: &NetworkDetails) {
        while let Some(child) = self.details_content.first_child() {
            self.details_content.remove(&child);
        }
        
        let ip4_dns_text = details.ipv4_dns.first()
            .cloned()
            .unwrap_or_else(|| "N/A".to_string());
        let ip6_dns_text = details.ipv6_dns.first()
            .cloned()
            .unwrap_or_else(|| "N/A".to_string());
        
        let ip_text = if details.ip4_address.is_empty() { "N/A" } else { details.ip4_address.as_str() };
        let ip6_text = if details.ip6_address.is_empty() { "N/A" } else { details.ip6_address.as_str() };
        let gateway_text = if details.gateway.is_empty() { "N/A" } else { details.gateway.as_str() };
        let mac_text = if details.mac_address.is_empty() { "N/A" } else { details.mac_address.as_str() };
        let speed_text = if details.connection_speed.is_empty() { "N/A" } else { details.connection_speed.as_str() };
        
        let rows: [(&str, &str, &str); 8] = [
            ("SSID", details.ssid.as_str(), "network-wireless-symbolic"),
            ("IPv4 Address", ip_text, "network-server-symbolic"),
            ("IPv6 Address", ip6_text, "network-server-symbolic"),
            ("Gateway", gateway_text, "network-vpn-symbolic"),
            ("IPv4 DNS", ip4_dns_text.as_str(), "system-run-symbolic"),
            ("IPv6 DNS", ip6_dns_text.as_str(), "system-run-symbolic"),
            ("MAC Address", mac_text, "dialog-password-symbolic"),
            ("Speed", speed_text, "network-transmit-receive-symbolic"),
        ];
        
        for (label, value, icon_name) in rows {
            let row = gtk::Box::builder()
                .orientation(Orientation::Horizontal)
                .css_classes(["orbit-details-row"])
                .spacing(8)
                .build();
            
            let icon = gtk::Image::builder()
                .icon_name(icon_name)
                .pixel_size(16)
                .css_classes(["orbit-detail-icon"])
                .valign(gtk::Align::Center)
                .build();
            
            let label_widget = gtk::Label::builder()
                .label(label)
                .css_classes(["orbit-detail-label"])
                .halign(gtk::Align::Start)
                .hexpand(true)
                .build();
            
            let value_widget = gtk::Label::builder()
                .label(value)
                .css_classes(["orbit-detail-value"])
                .halign(gtk::Align::End)
                .build();
            value_widget.set_ellipsize(gtk::pango::EllipsizeMode::End);
            value_widget.set_wrap(true);
            
            row.append(&icon);
            row.append(&label_widget);
            row.append(&value_widget);
            self.details_content.append(&row);
        }
        
        self.password_revealer.set_reveal_child(false);
        self.saved_revealer.set_reveal_child(false);
        self.hidden_revealer.set_reveal_child(false);
        self.error_revealer.set_reveal_child(false);
        self.details_revealer.set_reveal_child(true);
    }

    pub fn show_device_details(&self, details: &crate::dbus::bluez::BluetoothDeviceDetails) {
        while let Some(child) = self.details_content.first_child() {
            self.details_content.remove(&child);
        }
        
        let battery_text = details.battery_percentage
            .map(|p| format!("{}%", p))
            .unwrap_or_else(|| "N/A".to_string());
            
        let status_text = if details.is_connected {
            "Connected"
        } else if details.is_paired {
            "Paired"
        } else {
            "Available"
        };
        
        let rows = [
            ("Name", details.name.as_str(), "preferences-system-symbolic"),
            ("Address", details.address.as_str(), "dialog-password-symbolic"),
            ("Status", status_text, "network-wireless-symbolic"),
            ("Battery", battery_text.as_str(), "battery-good-symbolic"),
            ("Signal (RSSI)", &format!("{} dBm", details.rssi), "network-transmit-receive-symbolic"),
            ("Trusted", if details.is_trusted { "Yes" } else { "No" }, "security-high-symbolic"),
        ];
        
        for (label, value, icon_name) in rows {
            let row = gtk::Box::builder()
                .orientation(Orientation::Horizontal)
                .css_classes(["orbit-details-row"])
                .spacing(8)
                .build();
            
            let icon = gtk::Image::builder()
                .icon_name(icon_name)
                .pixel_size(16)
                .css_classes(["orbit-detail-icon"])
                .valign(gtk::Align::Center)
                .build();
            
            let label_widget = gtk::Label::builder()
                .label(label)
                .css_classes(["orbit-detail-label"])
                .halign(gtk::Align::Start)
                .hexpand(true)
                .build();
            
            let value_widget = gtk::Label::builder()
                .label(value)
                .css_classes(["orbit-detail-value"])
                .halign(gtk::Align::End)
                .build();
            value_widget.set_ellipsize(gtk::pango::EllipsizeMode::End);
            value_widget.set_wrap(true);

            row.append(&icon);
            row.append(&label_widget);
            row.append(&value_widget);
            self.details_content.append(&row);
        }

        // Add Trust/Untrust button
        let trust_btn = gtk::Button::builder()
            .label(if details.is_trusted { "Untrust Device" } else { "Trust Device" })
            .css_classes(if details.is_trusted { 
                vec!["orbit-button", "destructive", "flat"] 
            } else { 
                vec!["orbit-button", "primary", "flat"] 
            })
            .margin_top(8)
            .build();
        
        let path = details.path.clone();
        let is_trusted = details.is_trusted;
        let callback = self.details_callback.clone();
        trust_btn.connect_clicked(move |_| {
            if let Some(ref cb) = *callback.borrow() {
                cb(path.clone(), !is_trusted);
            }
        });
        
        self.details_content.append(&trust_btn);

        if details.is_paired {
            let forget_btn = gtk::Button::builder()
                .label("Forget Device")
                .css_classes(["orbit-button", "destructive", "flat"])
                .margin_top(4)
                .build();
            
            let path = details.path.clone();
            let forget_cb = self.forget_callback.clone();
            let details_rev = self.details_revealer.clone();
            forget_btn.connect_clicked(move |_| {
                if let Some(ref cb) = *forget_cb.borrow() {
                    details_rev.set_reveal_child(false);
                    cb(path.clone());
                }
            });
            self.details_content.append(&forget_btn);
        }
        
        self.password_revealer.set_reveal_child(false);
        self.saved_revealer.set_reveal_child(false);
        self.hidden_revealer.set_reveal_child(false);
        self.error_revealer.set_reveal_child(false);
        self.details_revealer.set_reveal_child(true);
    }

    pub fn set_on_details_action<F: Fn(String, bool) + 'static>(&self, callback: F) {
        *self.details_callback.borrow_mut() = Some(Rc::new(callback));
    }

    pub fn set_on_forget_device<F: Fn(String) + 'static>(&self, callback: F) {
        *self.forget_callback.borrow_mut() = Some(Rc::new(callback));
    }

    pub fn show_bt_pin_request(&self, device_name: &str, tx: async_channel::Sender<String>) {
        self.bt_agent_label.set_label(&format!("Enter PIN for {}:", device_name));
        self.bt_agent_entry.set_visible(true);
        self.bt_agent_entry.set_text("");
        self.bt_agent_entry.set_placeholder_text(Some("PIN"));
        self.bt_agent_confirm_btn.set_label("Pair");
        *self.bt_pin_callback.borrow_mut() = Some(tx);
        self.bt_agent_revealer.set_reveal_child(true);
        self.bt_agent_entry.grab_focus();
    }

    pub fn show_bt_passkey_request(&self, device_name: &str, tx: async_channel::Sender<u32>) {
        self.bt_agent_label.set_label(&format!("Enter Passkey for {}:", device_name));
        self.bt_agent_entry.set_visible(true);
        self.bt_agent_entry.set_text("");
        self.bt_agent_entry.set_placeholder_text(Some("Passkey (6 digits)"));
        self.bt_agent_confirm_btn.set_label("Pair");
        *self.bt_passkey_callback.borrow_mut() = Some(tx);
        self.bt_agent_revealer.set_reveal_child(true);
        self.bt_agent_entry.grab_focus();
    }

    pub fn show_bt_confirm_request(&self, device_name: &str, passkey: u32, tx: async_channel::Sender<bool>) {
        self.bt_agent_label.set_label(&format!("Does {} show passkey {:06}?", device_name, passkey));
        self.bt_agent_entry.set_visible(false);
        self.bt_agent_confirm_btn.set_label("Confirm");
        *self.bt_confirm_callback.borrow_mut() = Some(tx);
        self.bt_agent_revealer.set_reveal_child(true);
    }

    pub fn show_bt_pin_display(&self, device_name: &str, pincode: &str) {
        self.bt_agent_label.set_label(&format!("Pairing with {}. Enter this PIN on the device: {}", device_name, pincode));
        self.bt_agent_entry.set_visible(false);
        self.bt_agent_confirm_btn.set_label("Dismiss");
        self.bt_agent_revealer.set_reveal_child(true);
    }

    pub fn show_bt_passkey_display(&self, device_name: &str, passkey: u32) {
        self.bt_agent_label.set_label(&format!("Pairing with {}. Enter this passkey on the device: {:06}", device_name, passkey));
        self.bt_agent_entry.set_visible(false);
        self.bt_agent_confirm_btn.set_label("Dismiss");
        self.bt_agent_revealer.set_reveal_child(true);
    }

    pub fn cancel_bt_agent(&self) {
        self.bt_agent_revealer.set_reveal_child(false);
        let _ = self.bt_pin_callback.borrow_mut().take();
        let _ = self.bt_passkey_callback.borrow_mut().take();
        if let Some(tx) = self.bt_confirm_callback.borrow_mut().take() {
            let _ = tx.send_blocking(false);
        }
    }

    pub fn show_saved_networks(&self) {
        self.details_revealer.set_reveal_child(false);
        self.password_revealer.set_reveal_child(false);
        self.hidden_revealer.set_reveal_child(false);
        self.error_revealer.set_reveal_child(false);
        self.saved_revealer.set_reveal_child(true);
    }
    
    pub fn show_wired_overlay(&self, profiles: &[WiredProfile]) {
        self.hide_wired_overlay();
        
        while let Some(child) = self.wired_list_box.first_child() {
            self.wired_list_box.remove(&child);
        }
        
        for profile in profiles {
            let row = self.create_wired_device_row(profile);
            self.wired_list_box.append(&row);
        }
        
        self.wired_revealer.set_reveal_child(true);
    }
    
    fn create_wired_device_row(&self, profile: &WiredProfile) -> gtk::Box {
        let container = gtk::Box::builder()
            .orientation(Orientation::Vertical)
            .spacing(4)
            .css_classes(["orbit-wired-device-row"])
            .build();
        
        let main_row = gtk::Box::builder()
            .orientation(Orientation::Horizontal)
            .spacing(12)
            .build();
        
        let icon = gtk::Image::builder()
            .icon_name(if profile.is_active { "network-wired-symbolic" } else { "network-wired-disconnected-symbolic" })
            .pixel_size(24)
            .valign(gtk::Align::Center)
            .build();
        if profile.is_active {
            icon.add_css_class("orbit-icon-accent");
        }
        main_row.append(&icon);
        
        let info_box = gtk::Box::builder()
            .orientation(Orientation::Vertical)
            .spacing(2)
            .hexpand(true)
            .valign(gtk::Align::Center)
            .build();
        
        let name_label = gtk::Label::builder()
            .label(&profile.device_name)
            .css_classes(["orbit-ssid"])
            .halign(gtk::Align::Start)
            .build();
        info_box.append(&name_label);
        
        let status_text = if profile.is_active {
            if !profile.ip4_address.is_empty() {
                format!("Connected · {} · {} Mb/s", profile.ip4_address, profile.speed)
            } else {
                format!("Connected · {} Mb/s", profile.speed)
            }
        } else if profile.has_carrier {
            "Cable connected · Disconnected".to_string()
        } else {
            "No cable detected".to_string()
        };
        
        let status_label = gtk::Label::builder()
            .label(&status_text)
            .css_classes(["orbit-status"])
            .halign(gtk::Align::Start)
            .build();
        info_box.append(&status_label);
        
        main_row.append(&info_box);
        
        if profile.is_active && !profile.connection_path.is_empty() {
            let disc_btn = gtk::Button::builder()
                .label("Disconnect")
                .css_classes(["orbit-button", "flat"])
                .build();
            let dev_path = profile.device_path.clone();
            let cb = self.wired_disconnect_callback.clone();
            disc_btn.connect_clicked(move |_| {
                if let Some(ref f) = *cb.borrow() {
                    f(dev_path.clone());
                }
            });
            main_row.append(&disc_btn);
        } else if !profile.connection_path.is_empty() {
            let conn_btn = gtk::Button::builder()
                .label("Connect")
                .css_classes(["orbit-button", "flat", "primary"])
                .build();
            let conn_path = profile.connection_path.clone();
            let dev_path = profile.device_path.clone();
            let cb = self.wired_connect_callback.clone();
            conn_btn.connect_clicked(move |_| {
                if let Some(ref f) = *cb.borrow() {
                    f(conn_path.clone(), dev_path.clone());
                }
            });
            main_row.append(&conn_btn);
        }
        
        container.append(&main_row);
        
        // Expandable details section
        let has_details = profile.is_active || !profile.mac_address.is_empty();
        
        if has_details {
            let details_btn = gtk::Button::builder()
                .label("Details")
                .icon_name("pan-end-symbolic")
                .css_classes(["orbit-button", "flat"])
                .build();
            
            // Build details content
            let details_box = gtk::Box::builder()
                .orientation(Orientation::Vertical)
                .spacing(4)
                .margin_start(36)
                .margin_top(4)
                .build();
            
            if !profile.mac_address.is_empty() {
                let mac_label = gtk::Label::builder()
                    .label(&format!("MAC: {}", profile.mac_address))
                    .css_classes(["orbit-status"])
                    .halign(gtk::Align::Start)
                    .selectable(true)
                    .build();
                details_box.append(&mac_label);
            }
            
            if profile.is_active {
                if !profile.gateway.is_empty() {
                    let gw_label = gtk::Label::builder()
                        .label(&format!("Gateway: {}", profile.gateway))
                        .css_classes(["orbit-status"])
                        .halign(gtk::Align::Start)
                        .selectable(true)
                        .build();
                    details_box.append(&gw_label);
                }
                
                if !profile.dns_servers.is_empty() {
                    let dns_text = profile.dns_servers.join(", ");
                    let dns_label = gtk::Label::builder()
                        .label(&format!("DNS: {}", dns_text))
                        .css_classes(["orbit-status"])
                        .halign(gtk::Align::Start)
                        .selectable(true)
                        .wrap(true)
                        .build();
                    details_box.append(&dns_label);
                }
            }
            
            if !profile.connection_path.is_empty() {
                let auto_row = gtk::Box::builder()
                    .orientation(Orientation::Horizontal)
                    .spacing(8)
                    .halign(gtk::Align::Start)
                    .build();
                
                let auto_label = gtk::Label::builder()
                    .label("Auto-connect")
                    .css_classes(["orbit-status"])
                    .halign(gtk::Align::Start)
                    .build();
                
                let auto_switch = gtk::Switch::builder()
                    .active(profile.autoconnect)
                    .css_classes(["orbit-toggle-switch"])
                    .valign(gtk::Align::Center)
                    .build();
                
                auto_row.append(&auto_label);
                auto_row.append(&auto_switch);
                details_box.append(&auto_row);
                
                let conn_path = profile.connection_path.clone();
                let auto_cb = self.wired_autoconnect_callback.clone();
                auto_switch.connect_state_set(move |_, state| {
                    if let Some(ref f) = *auto_cb.borrow() {
                        f(conn_path.clone(), state);
                    }
                    gtk4::glib::Propagation::Proceed
                });
            }
            
            let details_revealer = gtk::Revealer::builder()
                .child(&details_box)
                .reveal_child(false)
                .transition_type(gtk::RevealerTransitionType::SlideDown)
                .transition_duration(200)
                .build();
            
            let details_btn_clone = details_btn.clone();
            let revealer_clone = details_revealer.clone();
            details_btn.connect_clicked(move |_| {
                let expanded = revealer_clone.reveals_child();
                revealer_clone.set_reveal_child(!expanded);
                if expanded {
                    details_btn_clone.set_icon_name("pan-end-symbolic");
                } else {
                    details_btn_clone.set_icon_name("pan-down-symbolic");
                }
            });
            
            container.append(&details_btn);
            container.append(&details_revealer);
        }
        
        container
    }
    
    pub fn hide_wired_overlay(&self) {
        self.wired_revealer.set_reveal_child(false);
    }
    
    pub fn set_wired_connect_callback<F: Fn(String, String) + 'static>(&self, callback: F) {
        *self.wired_connect_callback.borrow_mut() = Some(Rc::new(callback));
    }
    
    pub fn set_wired_disconnect_callback<F: Fn(String) + 'static>(&self, callback: F) {
        *self.wired_disconnect_callback.borrow_mut() = Some(Rc::new(callback));
    }
    
    pub fn set_wired_autoconnect_callback<F: Fn(String, bool) + 'static>(&self, callback: F) {
        *self.wired_autoconnect_callback.borrow_mut() = Some(Rc::new(callback));
    }
    
    pub fn window(&self) -> &gtk::ApplicationWindow {
        &self.window
    }

    pub fn set_tab(&self, tab_name: &str) {
        self.header.set_tab(tab_name);
        self.stack.set_visible_child_name(tab_name);
    }
}

fn sanitize_error_message(msg: &str) -> String {
    let msg_lower = msg.to_lowercase();
    if msg_lower.contains("bad-password") || msg_lower.contains("invalid-key") {
        "Incorrect password. Please try again.".to_string()
    } else if msg_lower.contains("timeout") {
        "Connection timed out.".to_string()
    } else if msg_lower.contains("busy") || msg_lower.contains("in progress") {
        "Device is busy. Please wait and try again.".to_string()
    } else if msg_lower.contains("adapter-not-powered") || msg_lower.contains("not powered") {
        "Bluetooth adapter is not powered on yet.".to_string()
    } else if msg_lower.contains("rfkill") || msg_lower.contains("blocked") {
        "Bluetooth is blocked by system (RFKill). Try unblocking it manually.".to_string()
    } else {
        msg.to_string()
    }
}

fn parse_revealer_transition(t: &str) -> gtk::RevealerTransitionType {
    match t.to_lowercase().as_str() {
        "slideright" => gtk::RevealerTransitionType::SlideRight,
        "slideleft" => gtk::RevealerTransitionType::SlideLeft,
        "slideup" => gtk::RevealerTransitionType::SlideUp,
        "slidedown" => gtk::RevealerTransitionType::SlideDown,
        "swingright" => gtk::RevealerTransitionType::SwingRight,
        "swingleft" => gtk::RevealerTransitionType::SwingLeft,
        "swingup" => gtk::RevealerTransitionType::SwingUp,
        "swingdown" => gtk::RevealerTransitionType::SwingDown,
        "fade" | "crossfade" => gtk::RevealerTransitionType::Crossfade,
        "none" => gtk::RevealerTransitionType::None,
        _ => gtk::RevealerTransitionType::SlideDown,
    }
}

fn parse_stack_transition(t: &str) -> gtk::StackTransitionType {
    match t.to_lowercase().as_str() {
        "slideright" => gtk::StackTransitionType::SlideRight,
        "slideleft" => gtk::StackTransitionType::SlideLeft,
        "slideup" => gtk::StackTransitionType::SlideUp,
        "slidedown" => gtk::StackTransitionType::SlideDown,
        "slidehorizontal" => gtk::StackTransitionType::SlideLeftRight,
        "slidevertical" => gtk::StackTransitionType::SlideUpDown,
        "crossfade" => gtk::StackTransitionType::Crossfade,
        "none" => gtk::StackTransitionType::None,
        _ => gtk::StackTransitionType::SlideLeftRight,
    }
}
