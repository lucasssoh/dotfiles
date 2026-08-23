//! Layer-shell window shell + WiFi overlays (password entry, hidden
//! network, saved networks, error toast). Anchored corner panel (like
//! Orbit, NOT a fullscreen 4-edge overlay like Roue/Prisme -- see the
//! project plan).

use gtk4::{self as gtk, prelude::*, Application, ApplicationWindow, Orientation, Overlay};
use gtk4_layer_shell::{Edge, KeyboardMode, Layer, LayerShell};
use std::cell::{Cell, RefCell};
use std::rc::Rc;

use super::header::Header;
use super::network_list::NetworkList;
use super::saved_list::SavedList;
use crate::config::Config;

pub struct BaliseWindow {
    window: ApplicationWindow,
    root_revealer: gtk::Revealer,
    config: Rc<RefCell<Config>>,
    header: Header,
    network_list: NetworkList,
    saved_list: SavedList,
    stack: gtk::Stack,
    fallback_css: gtk::CssProvider,
    user_css: gtk::CssProvider,
    is_animating: Rc<Cell<bool>>,

    password_revealer: gtk::Revealer,
    password_entry: gtk::PasswordEntry,
    password_label: gtk::Label,
    password_error_label: gtk::Label,
    password_connect_btn: gtk::Button,
    password_callback: Rc<RefCell<Option<Rc<dyn Fn(Option<String>)>>>>,

    hidden_revealer: gtk::Revealer,
    hidden_ssid_entry: gtk::Entry,
    hidden_password_entry: gtk::PasswordEntry,
    hidden_connect_btn: gtk::Button,
    hidden_callback: Rc<RefCell<Option<Rc<dyn Fn(Option<(String, String)>)>>>>,

    saved_revealer: gtk::Revealer,

    error_revealer: gtk::Revealer,
    error_label: gtk::Label,
}

/// Hard-fixed panel footprint -- `default_width`/`default_height` alone
/// are only an initial hint; GTK still auto-grows/shrinks a layer-shell
/// surface to match its content's natural size otherwise (confirmed
/// live: the panel visibly changed height between screenshots as its
/// network list populated). `width_request`/`height_request` below pin
/// it for real; content beyond this footprint scrolls internally
/// (ScrolledWindow) instead of resizing the window.
const PANEL_WIDTH: i32 = 360;
const PANEL_HEIGHT: i32 = 480;

impl BaliseWindow {
    pub fn new(app: &Application, config: Config) -> Self {
        let window = ApplicationWindow::builder()
            .application(app)
            .default_width(PANEL_WIDTH)
            .default_height(PANEL_HEIGHT)
            .width_request(PANEL_WIDTH)
            .height_request(PANEL_HEIGHT)
            .resizable(false)
            .decorated(false)
            .build();

        window.init_layer_shell();
        // Distinct namespace from "orbit" -- both run side by side during
        // the parallel build-out (see the project plan). Anchored corner
        // panel, not a fullscreen surface: KeyboardMode::None normally,
        // flipped to OnDemand only while shown (see show()/hide() below),
        // exclusive_zone 0 (doesn't reserve screen space like a bar would).
        window.set_namespace("balise");
        window.set_layer(Layer::Overlay);
        window.set_keyboard_mode(KeyboardMode::None);
        window.set_exclusive_zone(0);

        // Deliberately NOT calling window.add_css_class("background"):
        // that GTK class paints an opaque themed rectangle which ignores
        // border-radius -- confirmed live on Orbit this session as a
        // right-angle corner poking past its rounded panel once its
        // compositor blur was removed. Leaving it off means .balise-panel
        // (below) is the only thing ever painted; style.css also forces
        // window/.background transparent as defense-in-depth.

        let display = gtk4::gdk::Display::default().expect("no default display");
        let (fallback_css, user_css) = crate::theme::load(&display);

        let panel = gtk::Box::builder()
            .orientation(Orientation::Vertical)
            .css_classes(["balise-panel"])
            .vexpand(true)
            .hexpand(true)
            .overflow(gtk::Overflow::Hidden)
            .build();

        let header = Header::new();
        panel.append(header.widget());

        let stack = gtk::Stack::builder()
            .vexpand(true)
            .hexpand(true)
            .transition_type(parse_stack_transition(&config.stack_transition))
            .transition_duration(config.stack_transition_duration)
            .build();

        let network_list = NetworkList::new();
        let saved_list = SavedList::new();

        stack.add_named(network_list.widget(), Some("wifi"));
        stack.set_visible_child_name("wifi");
        // Minimum height so the panel doesn't collapse to nothing while
        // WiFi's list is empty/loading -- same purpose as Orbit's
        // stack.set_size_request, kept small since there's only one tab
        // today (see the project plan's Phase 2/3 for when this needs
        // revisiting for Ethernet/Bluetooth's own minimums).
        stack.set_size_request(300, 380);
        panel.append(&stack);

        let overlay = Overlay::new();
        overlay.set_child(Some(&panel));

        // ---- password overlay ------------------------------------------
        let password_box = gtk::Box::builder()
            .orientation(Orientation::Vertical)
            .spacing(12)
            .css_classes(["balise-password-overlay"])
            .margin_start(16)
            .margin_end(16)
            .margin_top(16)
            .margin_bottom(16)
            .build();
        let password_label = gtk::Label::builder()
            .label("Enter password:")
            .css_classes(["balise-detail-label"])
            .halign(gtk::Align::Start)
            .build();
        let password_entry = gtk::PasswordEntry::builder().placeholder_text("Password").hexpand(true).build();
        let password_error_label = gtk::Label::builder()
            .label("")
            .css_classes(["balise-error-text-small"])
            .halign(gtk::Align::Start)
            .visible(false)
            .build();
        let password_btn_row = gtk::Box::builder().orientation(Orientation::Horizontal).spacing(8).halign(gtk::Align::End).build();
        let password_cancel_btn = gtk::Button::builder().label("Cancel").css_classes(["balise-button", "flat"]).build();
        let password_connect_btn =
            gtk::Button::builder().label("Connect").css_classes(["balise-button", "primary", "flat"]).build();
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

        let rev = password_revealer.clone();
        let ent = password_entry.clone();
        password_cancel_btn.connect_clicked(move |_| {
            rev.set_reveal_child(false);
            ent.set_text("");
        });
        overlay.add_overlay(&password_revealer);

        // ---- hidden-network overlay -------------------------------------
        let hidden_box = gtk::Box::builder()
            .orientation(Orientation::Vertical)
            .spacing(12)
            .css_classes(["balise-password-overlay"])
            .margin_start(16)
            .margin_end(16)
            .margin_top(16)
            .margin_bottom(16)
            .build();
        let hidden_label = gtk::Label::builder()
            .label("Connect to Hidden Network")
            .css_classes(["balise-detail-label"])
            .halign(gtk::Align::Start)
            .build();
        let hidden_ssid_entry = gtk::Entry::builder().placeholder_text("Network Name (SSID)").hexpand(true).build();
        let hidden_password_entry =
            gtk::PasswordEntry::builder().placeholder_text("Password (Optional)").hexpand(true).build();
        let hidden_btn_row = gtk::Box::builder().orientation(Orientation::Horizontal).spacing(8).halign(gtk::Align::End).build();
        let hidden_cancel_btn = gtk::Button::builder().label("Cancel").css_classes(["balise-button", "flat"]).build();
        let hidden_connect_btn =
            gtk::Button::builder().label("Connect").css_classes(["balise-button", "primary", "flat"]).build();
        hidden_btn_row.append(&hidden_cancel_btn);
        hidden_btn_row.append(&hidden_connect_btn);
        hidden_box.append(&hidden_label);
        hidden_box.append(&hidden_ssid_entry);
        hidden_box.append(&hidden_password_entry);
        hidden_box.append(&hidden_btn_row);

        let hidden_revealer = gtk::Revealer::builder()
            .child(&hidden_box)
            .reveal_child(false)
            .transition_type(gtk::RevealerTransitionType::SlideUp)
            .transition_duration(250)
            .valign(gtk::Align::End)
            .can_target(true)
            .build();
        let rev = hidden_revealer.clone();
        hidden_cancel_btn.connect_clicked(move |_| rev.set_reveal_child(false));
        overlay.add_overlay(&hidden_revealer);

        // ---- saved-networks overlay -------------------------------------
        let saved_box = gtk::Box::builder()
            .orientation(Orientation::Vertical)
            .css_classes(["balise-password-overlay"])
            .spacing(8)
            .width_request(300)
            .build();
        let saved_header_row = gtk::Box::builder().orientation(Orientation::Horizontal).spacing(12).build();
        let saved_title = gtk::Label::builder()
            .label("Saved Networks")
            .css_classes(["balise-detail-label"])
            .halign(gtk::Align::Start)
            .hexpand(true)
            .build();
        let saved_close_btn =
            gtk::Button::builder().icon_name("window-close-symbolic").css_classes(["balise-button", "flat"]).build();
        saved_header_row.append(&saved_title);
        saved_header_row.append(&saved_close_btn);
        saved_box.append(&saved_header_row);

        let saved_list_widget = saved_list.widget().clone();
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
        let rev = saved_revealer.clone();
        saved_close_btn.connect_clicked(move |_| rev.set_reveal_child(false));
        overlay.add_overlay(&saved_revealer);

        // ---- error toast --------------------------------------------------
        let error_box = gtk::Box::builder()
            .orientation(Orientation::Vertical)
            .spacing(8)
            .css_classes(["balise-error-overlay"])
            .margin_start(16)
            .margin_end(16)
            .margin_top(16)
            .margin_bottom(16)
            .build();
        let error_header = gtk::Box::builder().orientation(Orientation::Horizontal).spacing(8).build();
        let error_icon = gtk::Image::builder().icon_name("dialog-error-symbolic").pixel_size(16).valign(gtk::Align::Center).build();
        let error_title = gtk::Label::builder()
            .label("Error")
            .css_classes(["balise-error-title"])
            .halign(gtk::Align::Start)
            .hexpand(true)
            .build();
        let error_close_btn =
            gtk::Button::builder().icon_name("window-close-symbolic").css_classes(["balise-button", "flat"]).build();
        error_header.append(&error_icon);
        error_header.append(&error_title);
        error_header.append(&error_close_btn);
        let error_label =
            gtk::Label::builder().label("").css_classes(["balise-error-text"]).halign(gtk::Align::Start).wrap(true).build();
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
        let rev = error_revealer.clone();
        error_close_btn.connect_clicked(move |_| rev.set_reveal_child(false));
        overlay.add_overlay(&error_revealer);

        // Deliberately NOT valign(Start) here (unlike Orbit/Phase 0, where
        // the window's size was only a hint and content sat at its
        // natural size within whatever GTK gave it): the window is now
        // hard-fixed to PANEL_WIDTH x PANEL_HEIGHT (see width_request/
        // height_request above), so panel/overlay/root_revealer need to
        // actually FILL that footprint via vexpand, or the difference
        // between their natural content height and the fixed window
        // height shows up as a flat, untextured dead zone at the bottom
        // -- confirmed live: it read as a plain rectangle with none of
        // the row/button/border glass treatment, since nothing was
        // painting it but the bare panel fill under an unfilled gap.

        let root_revealer = gtk::Revealer::builder()
            .transition_type(parse_revealer_transition(&config.window_transition))
            .transition_duration(config.window_transition_duration)
            .child(&overlay)
            .build();

        window.set_child(Some(&root_revealer));

        let win = Self {
            window,
            root_revealer,
            config: Rc::new(RefCell::new(config)),
            header,
            network_list,
            saved_list,
            stack,
            fallback_css,
            user_css,
            is_animating: Rc::new(Cell::new(false)),
            password_revealer,
            password_entry,
            password_label,
            password_error_label,
            password_connect_btn,
            password_callback: Rc::new(RefCell::new(None)),
            hidden_revealer,
            hidden_ssid_entry,
            hidden_password_entry,
            hidden_connect_btn,
            hidden_callback: Rc::new(RefCell::new(None)),
            saved_revealer,
            error_revealer,
            error_label,
        };
        win.apply_position();
        win
    }

    pub fn stack(&self) -> &gtk::Stack {
        &self.stack
    }

    pub fn header(&self) -> &Header {
        &self.header
    }

    pub fn network_list(&self) -> &NetworkList {
        &self.network_list
    }

    pub fn saved_list(&self) -> &SavedList {
        &self.saved_list
    }

    /// Show/hide, adapted from orbit-vendor/src/ui/window.rs:799-846. The
    /// `is_animating` re-entrancy guard stops a fast double-toggle from
    /// leaving the panel half-revealed.
    pub fn show(&self) {
        if self.is_animating.get() {
            return;
        }
        self.is_animating.set(true);

        self.window.set_visible(true);
        self.window.present();
        // OnDemand while shown -- this is what makes the WiFi password
        // entry typable while the panel is open, without permanently
        // stealing keyboard focus from the rest of the desktop while
        // it's hidden.
        self.window.set_keyboard_mode(KeyboardMode::OnDemand);

        let rev = self.root_revealer.clone();
        let anim = self.is_animating.clone();
        let duration = self.config.borrow().window_transition_duration;

        gtk::glib::idle_add_local_once(move || {
            rev.set_reveal_child(true);
            gtk::glib::timeout_add_local(std::time::Duration::from_millis(duration.into()), move || {
                anim.set(false);
                gtk::glib::ControlFlow::Break
            });
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

        gtk::glib::timeout_add_local(std::time::Duration::from_millis(duration.into()), move || {
            window.set_visible(false);
            window.set_keyboard_mode(KeyboardMode::None);
            anim.set(false);
            gtk::glib::ControlFlow::Break
        });
    }

    pub fn set_position(&self, pos_str: &str) {
        self.config.borrow_mut().position = pos_str.to_string();
        self.apply_position();
    }

    /// Adapted from orbit-vendor/src/ui/window.rs:877-928 (identical
    /// nine-position scheme, defaulting to top-right).
    pub fn apply_position(&self) {
        let config = self.config.borrow();

        self.window.set_margin(Edge::Top, config.margin_top);
        self.window.set_margin(Edge::Bottom, config.margin_bottom);
        self.window.set_margin(Edge::Left, config.margin_left);
        self.window.set_margin(Edge::Right, config.margin_right);

        self.window.set_anchor(Edge::Top, false);
        self.window.set_anchor(Edge::Bottom, false);
        self.window.set_anchor(Edge::Left, false);
        self.window.set_anchor(Edge::Right, false);

        match config.position.as_str() {
            "top-left" => {
                self.window.set_anchor(Edge::Top, true);
                self.window.set_anchor(Edge::Left, true);
            }
            "top-center" => {
                self.window.set_anchor(Edge::Top, true);
            }
            "center-left" => {
                self.window.set_anchor(Edge::Left, true);
            }
            "center" => {}
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
        drop(config);
        self.apply_position();
        self.root_revealer
            .set_transition_type(parse_revealer_transition(&self.config.borrow().window_transition));
    }

    pub fn apply_theme(&self) {
        crate::theme::reload(&self.user_css);
        let _ = &self.fallback_css;
    }

    // ---- overlays -------------------------------------------------------

    /// Adapted from orbit-vendor/src/ui/window.rs:946-967.
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

        self.saved_revealer.set_reveal_child(false);
        self.hidden_revealer.set_reveal_child(false);
        self.password_revealer.set_reveal_child(true);
        self.password_entry.grab_focus();
    }

    pub fn hide_password_dialog(&self) {
        self.password_revealer.set_reveal_child(false);
        self.password_entry.set_text("");
    }

    /// Adapted from orbit-vendor/src/ui/window.rs:974-996.
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

        self.saved_revealer.set_reveal_child(false);
        self.password_revealer.set_reveal_child(false);
        self.hidden_revealer.set_reveal_child(true);
        self.hidden_ssid_entry.grab_focus();
    }

    pub fn show_saved_networks(&self) {
        self.password_revealer.set_reveal_child(false);
        self.hidden_revealer.set_reveal_child(false);
        self.saved_revealer.set_reveal_child(true);
    }

    /// Adapted from orbit-vendor/src/ui/window.rs:998-1007 -- auto-hides
    /// after 5s.
    pub fn show_error(&self, msg: &str) {
        self.error_label.set_label(&sanitize_error_message(msg));
        self.error_revealer.set_reveal_child(true);

        let rev = self.error_revealer.clone();
        gtk::glib::timeout_add_local(std::time::Duration::from_secs(5), move || {
            rev.set_reveal_child(false);
            gtk::glib::ControlFlow::Break
        });
    }
}

fn parse_revealer_transition(t: &str) -> gtk::RevealerTransitionType {
    match t {
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
    match t {
        "slideright" => gtk::StackTransitionType::SlideRight,
        "slideleft" => gtk::StackTransitionType::SlideLeft,
        "slideup" => gtk::StackTransitionType::SlideUp,
        "slidedown" => gtk::StackTransitionType::SlideDown,
        "slidehorizontal" => gtk::StackTransitionType::SlideLeftRight,
        "fade" | "crossfade" => gtk::StackTransitionType::Crossfade,
        "none" => gtk::StackTransitionType::None,
        _ => gtk::StackTransitionType::SlideLeftRight,
    }
}

/// Adapted from orbit-vendor/src/ui/window.rs:1498-1513.
fn sanitize_error_message(msg: &str) -> String {
    let lower = msg.to_lowercase();
    if lower.contains("bad-password") || lower.contains("invalid-key") {
        "Incorrect password. Please try again.".to_string()
    } else if lower.contains("timeout") {
        "Connection timed out.".to_string()
    } else if lower.contains("busy") || lower.contains("in progress") {
        "Device is busy. Please wait and try again.".to_string()
    } else {
        msg.to_string()
    }
}
