//! Layer-shell window shell + overlays (hidden network, saved networks,
//! error toast, Bluetooth pairing agent) + the endpoint detail page.
//! Anchored corner panel (like Orbit, NOT a fullscreen 4-edge overlay
//! like Roue/Prisme -- see the project plan).
//!
//! WiFi password entry is deliberately NOT an overlay here: it expands
//! inline under its own network row (ui/network_list.rs).

use gtk4::{self as gtk, prelude::*, Application, ApplicationWindow, Orientation, Overlay};
use gtk4_layer_shell::{Edge, KeyboardMode, Layer, LayerShell};
use std::cell::{Cell, RefCell};
use std::rc::Rc;

use super::detail::{DetailTarget, DetailView};
use super::device_list::DeviceList;
use super::header::Header;
use super::network_list::NetworkList;
use super::saved_list::SavedList;
use super::wired_list::WiredList;
use crate::config::Config;

pub struct BaliseWindow {
    window: ApplicationWindow,
    root_revealer: gtk::Revealer,
    config: Rc<RefCell<Config>>,
    header: Header,
    network_list: NetworkList,
    saved_list: SavedList,
    device_list: DeviceList,
    wired_list: WiredList,
    detail_view: DetailView,
    /// Tab to return to when leaving the detail page.
    detail_origin: Rc<RefCell<String>>,
    stack: gtk::Stack,
    fallback_css: gtk::CssProvider,
    user_css: gtk::CssProvider,
    is_animating: Rc<Cell<bool>>,

    hidden_revealer: gtk::Revealer,
    hidden_ssid_entry: gtk::Entry,
    hidden_password_entry: gtk::PasswordEntry,
    hidden_connect_btn: gtk::Button,
    hidden_callback: Rc<RefCell<Option<Rc<dyn Fn(Option<(String, String)>)>>>>,

    saved_revealer: gtk::Revealer,

    error_revealer: gtk::Revealer,
    error_label: gtk::Label,

    // Bluetooth pairing agent (Phase 3) -- one reusable overlay for PIN
    // entry, passkey entry, passkey/PIN display, and yes/no confirmation,
    // adapted from orbit-vendor/src/ui/window.rs's bt_agent_* fields.
    bt_agent_revealer: gtk::Revealer,
    bt_agent_label: gtk::Label,
    bt_agent_entry: gtk::Entry,
    bt_agent_confirm_btn: gtk::Button,
    bt_agent_cancel_btn: gtk::Button,
    bt_pin_callback: Rc<RefCell<Option<async_channel::Sender<String>>>>,
    bt_passkey_callback: Rc<RefCell<Option<async_channel::Sender<u32>>>>,
    bt_confirm_callback: Rc<RefCell<Option<async_channel::Sender<bool>>>>,
}

/// Hard-fixed panel footprint -- `default_width`/`default_height` alone
/// are only an initial hint; GTK still auto-grows/shrinks a layer-shell
/// surface to match its content's natural size otherwise (confirmed
/// live: the panel visibly changed height between screenshots as its
/// network list populated). `width_request`/`height_request` below pin
/// it for real; content beyond this footprint scrolls internally
/// (ScrolledWindow) instead of resizing the window.
///
/// 360 -> 351 so the panel lines up exactly with the quickshell "tools"
/// pill sitting directly above it (measured at 351 wide, right margin 6
/// -- config.toml's margin_right matches). It used to overhang that pill
/// by 25px on the left, which read as a misalignment.
///
/// Note this is only a MINIMUM: content wider than it still wins. Until
/// the row status labels were ellipsized, the panel measured 374 here no
/// matter what this constant said.
const PANEL_WIDTH: i32 = 351;
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
        // The namespace is what hypr/windowrules.lua matches on. Anchored
        // corner panel, not a fullscreen surface: KeyboardMode::None normally,
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

        // Glass border, take two: the "background-clip: padding-box,
        // border-box" longhand trick (works for Orbit/Roue/swaync) turned
        // out to render NOTHING in the border-box ring here -- confirmed
        // at the pixel level (sampled the raw screenshot buffer): with
        // border: 2.5px the ring was flat black with zero gradient
        // pixels, and even blown up to border: 20px as a diagnostic, the
        // ring stayed solid black instead of showing the gradient, while
        // the window did grow to make room for it (so the border-WIDTH
        // was respected, just never painted). Rather than chase why this
        // one surface/widget combination breaks the clip trick, switched
        // to the classically robust way to fake a gradient border in
        // CSS: two nested boxes. `panel` (outer, .balise-panel) is
        // painted with the gradient as a single plain `background`
        // filling its entire bounds; `panel_inner` (.balise-panel-inner)
        // sits inside it with a small margin, carrying the actual opaque
        // fill + all the real content -- the uncovered margin ring IS
        // the border, no clip-box ambiguity possible.
        let panel = gtk::Box::builder()
            .css_classes(["balise-panel"])
            .vexpand(true)
            .hexpand(true)
            .build();

        let panel_inner = gtk::Box::builder()
            .orientation(Orientation::Vertical)
            .css_classes(["balise-panel-inner"])
            .vexpand(true)
            .hexpand(true)
            .overflow(gtk::Overflow::Hidden)
            .build();
        panel.append(&panel_inner);

        let header = Header::new();
        panel_inner.append(header.widget());

        let stack = gtk::Stack::builder()
            .vexpand(true)
            .hexpand(true)
            .transition_type(parse_stack_transition(&config.stack_transition))
            .transition_duration(config.stack_transition_duration)
            .build();

        let network_list = NetworkList::new();
        let saved_list = SavedList::new();
        let device_list = DeviceList::new();
        let wired_list = WiredList::new();
        let detail_view = DetailView::new();

        stack.add_named(network_list.widget(), Some("wifi"));
        stack.add_named(device_list.widget(), Some("bluetooth"));
        stack.add_named(wired_list.widget(), Some("ethernet"));
        // Added last on purpose: with a slide transition, GTK animates
        // according to child order, so entering the detail page slides
        // in from the right and going back slides out to the right --
        // which is what "drilling in" should feel like.
        stack.add_named(detail_view.widget(), Some("detail"));
        stack.set_visible_child_name("wifi");
        stack.set_size_request(270, 380);
        panel_inner.append(&stack);

        let overlay = Overlay::new();
        overlay.set_child(Some(&panel));

        // The WiFi password overlay that used to live here is gone:
        // password entry is now inline, expanding under the network's
        // own row (see ui/network_list.rs::build_password_form). That
        // keeps the field visually attached to the network it belongs
        // to, and drops this panel from six stacked overlays to four.

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
            .width_request(270)
            .build();
        let saved_header_row = gtk::Box::builder().orientation(Orientation::Horizontal).spacing(12).build();
        let saved_title = gtk::Label::builder()
            .label("Saved Networks")
            .css_classes(["balise-detail-label"])
            .halign(gtk::Align::Start)
            .hexpand(true)
            .build();
        let saved_close_btn = gtk::Button::builder()
            .child(&super::icon::icon_label(super::icon::X))
            .css_classes(["balise-button", "flat"])
            .build();
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
        let error_icon = super::icon::icon_label(super::icon::WARNING_CIRCLE);
        error_icon.set_valign(gtk::Align::Center);
        let error_title = gtk::Label::builder()
            .label("Error")
            .css_classes(["balise-error-title"])
            .halign(gtk::Align::Start)
            .hexpand(true)
            .build();
        let error_close_btn = gtk::Button::builder()
            .child(&super::icon::icon_label(super::icon::X))
            .css_classes(["balise-button", "flat"])
            .build();
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

        // ---- Bluetooth pairing agent overlay (Phase 3) ---------------------
        // One reusable box for all five request kinds (PIN entry/display,
        // passkey entry/display, yes-no confirmation); which callback slot
        // is occupied (see app/mod.rs) decides what the Confirm button
        // does. Adapted from orbit-vendor/src/ui/window.rs's bt_agent_box.
        let bt_agent_box = gtk::Box::builder()
            .orientation(Orientation::Vertical)
            .spacing(12)
            .css_classes(["balise-password-overlay"])
            .margin_start(16)
            .margin_end(16)
            .margin_top(16)
            .margin_bottom(16)
            .build();
        let bt_agent_label =
            gtk::Label::builder().label("").css_classes(["balise-detail-label"]).halign(gtk::Align::Start).wrap(true).build();
        let bt_agent_entry = gtk::Entry::builder().hexpand(true).build();
        let bt_agent_btn_row = gtk::Box::builder().orientation(Orientation::Horizontal).spacing(8).halign(gtk::Align::End).build();
        let bt_agent_cancel_btn = gtk::Button::builder().label("Cancel").css_classes(["balise-button", "flat"]).build();
        let bt_agent_confirm_btn = gtk::Button::builder().label("Confirm").css_classes(["balise-button", "primary", "flat"]).build();
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

        let bt_pin_callback: Rc<RefCell<Option<async_channel::Sender<String>>>> = Rc::new(RefCell::new(None));
        let bt_passkey_callback: Rc<RefCell<Option<async_channel::Sender<u32>>>> = Rc::new(RefCell::new(None));
        let bt_confirm_callback: Rc<RefCell<Option<async_channel::Sender<bool>>>> = Rc::new(RefCell::new(None));

        // Disambiguates purely by which slot is occupied (pin -> passkey
        // -> confirm), using take() so a slot fires once -- adapted from
        // orbit-vendor/src/ui/window.rs:649-673.
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
            device_list,
            wired_list,
            detail_view,
            detail_origin: Rc::new(RefCell::new("wifi".to_string())),
            stack,
            fallback_css,
            user_css,
            is_animating: Rc::new(Cell::new(false)),
            hidden_revealer,
            hidden_ssid_entry,
            hidden_password_entry,
            hidden_connect_btn,
            hidden_callback: Rc::new(RefCell::new(None)),
            saved_revealer,
            error_revealer,
            error_label,
            bt_agent_revealer,
            bt_agent_label,
            bt_agent_entry,
            bt_agent_confirm_btn,
            bt_agent_cancel_btn,
            bt_pin_callback,
            bt_passkey_callback,
            bt_confirm_callback,
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

    pub fn device_list(&self) -> &DeviceList {
        &self.device_list
    }

    pub fn wired_list(&self) -> &WiredList {
        &self.wired_list
    }

    pub fn detail_view(&self) -> &DetailView {
        &self.detail_view
    }

    /// Switches the visible tab, using the transition from config
    /// (`stack_transition`, now a crossfade by default -- the three tabs
    /// are siblings, not a sequence, so sliding them implied a
    /// left/right ordering that doesn't exist).
    ///
    /// The guard matters: the back button calls `leave_detail` (which
    /// slides) and then re-activates the same tab, and without it we'd
    /// reset the transition type in the middle of that slide.
    pub fn show_tab(&self, tab: &str) {
        let already_there = self.stack.visible_child_name().map(|n| n.to_string()).as_deref() == Some(tab);
        if !already_there {
            self.stack.set_transition_type(parse_stack_transition(&self.config.borrow().stack_transition));
            self.stack.set_visible_child_name(tab);
        }
        self.header.set_tab(tab);
    }

    /// Drill in: swap the header for "‹ name" and slide the detail page
    /// in. Remembers which tab we came from so `leave_detail` returns
    /// there rather than to a hardcoded default.
    pub fn show_detail(&self, target: DetailTarget) {
        *self.detail_origin.borrow_mut() = target.origin_tab().to_string();
        self.header.set_detail_mode(Some(&target.title()));
        self.detail_view.set_target(target);
        // Deliberately NOT the configured tab transition: drilling in is
        // a sequence (list -> item), so it keeps a directional slide even
        // though the tabs themselves crossfade. `detail` is the last
        // stack child, so SlideLeftRight brings it in from the right and
        // takes it back out to the right.
        self.stack.set_transition_type(gtk::StackTransitionType::SlideLeftRight);
        self.stack.set_visible_child_name("detail");
    }

    /// Back out of the detail page. Returns the tab name restored, so
    /// the caller can resync that tab's state (app/mod.rs re-reads the
    /// radio + list for it).
    pub fn leave_detail(&self) -> String {
        let origin = self.detail_origin.borrow().clone();
        self.header.set_detail_mode(None);
        self.stack.set_transition_type(gtk::StackTransitionType::SlideLeftRight);
        self.stack.set_visible_child_name(&origin);
        origin
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
        self.hidden_revealer.set_reveal_child(true);
        self.hidden_ssid_entry.grab_focus();
    }

    pub fn show_saved_networks(&self) {
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

    // ---- Bluetooth pairing agent (Phase 3) -------------------------------
    // Adapted from orbit-vendor/src/ui/window.rs:1197-1248.

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
