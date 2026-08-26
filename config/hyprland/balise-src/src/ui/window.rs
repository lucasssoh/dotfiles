//! Layer-shell window shell + overlays (error toast, Bluetooth pairing
//! agent) + Stack sub-pages (endpoint detail, saved networks, hidden
//! network). Saved networks and the hidden-network form used to be
//! overlays too (bottom-sheet Revealers stacked on top of the current
//! tab) -- moved into the Stack instead, alongside the endpoint detail
//! page, so they get the panel's full width/height and the same
//! "‹ title" header navigation instead of popping up on top of
//! whatever tab happened to be showing underneath. Anchored corner
//! panel (like Orbit, NOT a fullscreen 4-edge overlay like Roue/Prisme
//! -- see the project plan). "Click anywhere else
//! closes it" is handled OUTSIDE this file entirely, by
//! hypr/scripts/balise-autoclose.sh listening for Hyprland's own
//! `activewindow` event and calling `balise hide` -- same trick the
//! comment there notes swaync already relies on. A real click-catching
//! surface spanning the whole output (Roue's own shape) was considered
//! here too, but rejected: it would block every click on the rest of the
//! screen while Balise is open, not just ones meant to dismiss it, which
//! the IPC-event approach never does. `close_bar` below is the one
//! genuinely new close affordance this file adds: an explicit, always-
//! visible control, for whoever doesn't already know clicking elsewhere
//! works.
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
    close_bar: gtk::Button,
    fallback_css: gtk::CssProvider,
    user_css: gtk::CssProvider,
    is_animating: Rc<Cell<bool>>,

    hidden_ssid_entry: gtk::Entry,
    hidden_password_entry: gtk::PasswordEntry,
    hidden_connect_btn: gtk::Button,
    hidden_cancel_btn: gtk::Button,

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

        // Glass border, take three. Take two (the two-nested-boxes trick,
        // see the git history on this comment) fixed the border itself
        // rendering as flat black, but both boxes were still plain CSS
        // rounded rects -- fine for straight-edged corners, a dead end
        // for the CRT-style bend asked for on this panel (matching
        // Quickshell's bar pills): GTK CSS's border-radius only does
        // elliptical CORNERS, there's no clip-path, so a straight edge
        // bulging outward in the middle can't be written in style.css no
        // matter the property. `CrtFrame` (ui/crt_frame.rs) draws both
        // curves itself with gsk::PathBuilder instead -- the outer one
        // filled with the same border gradient `.balise-panel` used to
        // paint via CSS (copied into Rust, see that file), the inner one
        // used as a clip for `panel_inner` below, which keeps its own
        // CSS background/padding/content completely unchanged and just
        // gets cut to the curve for free.
        //
        // `panel` still exists, now just for `.balise-panel`'s
        // box-shadow (style.css strips its background/border-radius
        // duties, CrtFrame owns those) -- CSS box-shadow needs a real
        // CSS-styled widget to hang off, painting it isn't something
        // CrtFrame's own snapshot() reproduces.
        let panel = gtk::Box::builder()
            .css_classes(["balise-panel"])
            .vexpand(true)
            .hexpand(true)
            .build();

        let crt_frame = super::crt_frame::CrtFrame::new();
        crt_frame.set_vexpand(true);
        crt_frame.set_hexpand(true);
        panel.append(&crt_frame);

        let panel_inner = gtk::Box::builder()
            .orientation(Orientation::Vertical)
            .css_classes(["balise-panel-inner"])
            .vexpand(true)
            .hexpand(true)
            .overflow(gtk::Overflow::Hidden)
            .build();
        crt_frame.set_child(&panel_inner);

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

        // Hidden-network form -- a real Stack page now (see the header
        // comment at the top of this file), not a bottom-sheet Revealer
        // floating on top of the WiFi tab. No title Label of its own: the
        // header's own "‹ Connect to Hidden Network" (set by
        // show_hidden_network()) carries that, same as the detail page
        // never repeats its own title inline. Connect/Cancel are wired in
        // app/mod.rs (both need to navigate the Stack back and Connect
        // needs the app-level `tx` channel), not here -- window.rs only
        // builds the widgets.
        let hidden_box = gtk::Box::builder().orientation(Orientation::Vertical).spacing(12).build();
        let hidden_ssid_entry = gtk::Entry::builder().placeholder_text("Network Name (SSID)").hexpand(true).build();
        let hidden_password_entry =
            gtk::PasswordEntry::builder().placeholder_text("Password (Optional)").hexpand(true).build();
        let hidden_btn_row = gtk::Box::builder().orientation(Orientation::Horizontal).spacing(8).halign(gtk::Align::End).build();
        let hidden_cancel_btn = gtk::Button::builder().label("Cancel").css_classes(["balise-button", "flat"]).build();
        let hidden_connect_btn =
            gtk::Button::builder().label("Connect").css_classes(["balise-button", "primary", "flat"]).build();
        hidden_btn_row.append(&hidden_cancel_btn);
        hidden_btn_row.append(&hidden_connect_btn);
        hidden_box.append(&hidden_ssid_entry);
        hidden_box.append(&hidden_password_entry);
        hidden_box.append(&hidden_btn_row);

        stack.add_named(network_list.widget(), Some("wifi"));
        stack.add_named(device_list.widget(), Some("bluetooth"));
        stack.add_named(wired_list.widget(), Some("ethernet"));
        // Saved networks -- also a real Stack page now, just the list
        // itself (SavedList never had a title of its own either; same
        // header-driven "‹ Saved Networks" as the hidden-network page
        // above).
        stack.add_named(saved_list.widget(), Some("saved"));
        stack.add_named(&hidden_box, Some("hidden"));
        // Added last on purpose: with a slide transition, GTK animates
        // according to child order, so entering the detail page slides
        // in from the right and going back slides out to the right --
        // which is what "drilling in" should feel like. Same reason
        // "saved"/"hidden" are added right before it rather than among
        // the three tabs above: all four are reached the same way (a
        // button on the WiFi tab, or a row's gear), so they should all
        // slide in from the right the same way too.
        stack.add_named(detail_view.widget(), Some("detail"));
        stack.set_visible_child_name("wifi");
        stack.set_size_request(270, 380);
        panel_inner.append(&stack);

        // Small close affordance at the bottom of the panel -- "une petite
        // pile large en bas pour fermer", asked for as an explicit,
        // discoverable way to dismiss Balise alongside clicking anywhere
        // else (handled outside this file, see the header comment at the
        // top of window.rs). No icon child (asked to read as "une barre
        // fine pleine", a thin solid bar/handle -- not a labeled button):
        // the widget is still a real Button underneath (click target +
        // accessibility), style.css just draws it as a plain thin strip,
        // no hover state. Wired in app/mod.rs's setup_ui_callbacks, same
        // as the tab buttons -- window.rs only builds the widget, it
        // doesn't own app-level show/hide state.
        // "flat" (GTK's own stock class) strips the theme's default
        // button chrome (background/border/hover overlay) so nothing
        // fights with the plain CSS bar drawn above -- same reason every
        // other custom-styled button in this panel also carries it.
        // Capped at a third of PANEL_WIDTH and centered (asked for,
        // after the first full-width pass read as too heavy) --
        // width_request + halign(Center) rather than a CSS max-width,
        // since a Box child defaults to Fill/hexpand-stretch and GTK CSS
        // has no reliable max-width for that.
        let close_bar = gtk::Button::builder()
            .css_classes(["balise-close-bar", "flat"])
            .halign(gtk::Align::Center)
            .width_request(PANEL_WIDTH / 3)
            .build();
        panel_inner.append(&close_bar);

        let overlay = Overlay::new();
        overlay.set_child(Some(&panel));

        // The WiFi password overlay that used to live here is gone:
        // password entry is now inline, expanding under the network's
        // own row (see ui/network_list.rs::build_password_form). Saved
        // networks and the hidden-network form (used to be two more
        // overlays right here) are Stack pages now instead -- see the
        // header comment at the top of this file and `hidden_box`/
        // `stack.add_named` above. That's what actually dropped this
        // panel from six stacked overlays to two (error toast + the
        // Bluetooth pairing agent, below).

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

        // Drives show()/hide()'s actual window-visibility flip off GTK's
        // own `child-revealed` property instead of a glib::timeout_add_local
        // guessed to match `window_transition_duration` -- that guessed
        // timer raced the real transition clock, and losing the race (the
        // window unmapping a frame or two before/after the Revealer
        // visually finished collapsing) is what showed up live as a brief
        // leftover sliver of the panel still on screen right at the end of
        // the close animation. is_child_revealed() is GTK's own ground
        // truth for "the transition is REALLY done", so there's no longer
        // a race to lose. Connected once here rather than per show()/
        // hide() call, which would leak a new handler on every open/close
        // (the hidden-network Connect button used to have exactly that
        // bug, back when it was rewired inside every show_hidden_dialog()
        // call -- fixed by moving its wiring to app/mod.rs instead, see
        // show_hidden_network() below).
        let is_animating = Rc::new(Cell::new(false));
        {
            let window = window.clone();
            let anim = is_animating.clone();
            root_revealer.connect_child_revealed_notify(move |rev| {
                if rev.is_child_revealed() {
                    // Show finished revealing -- window is already visible
                    // and keyboard-interactive from show() itself, this
                    // just clears the debounce guard.
                    anim.set(false);
                } else {
                    // Hide finished collapsing -- actually unmap now.
                    window.set_visible(false);
                    window.set_keyboard_mode(KeyboardMode::None);
                    anim.set(false);
                }
            });
        }

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
            close_bar,
            fallback_css,
            user_css,
            is_animating,
            hidden_ssid_entry,
            hidden_password_entry,
            hidden_connect_btn,
            hidden_cancel_btn,
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

    /// The bottom close bar -- app/mod.rs wires its click to the same
    /// Hide path `balise-autoclose.sh` drives.
    pub fn close_bar(&self) -> &gtk::Button {
        &self.close_bar
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
    /// leaving the panel half-revealed. The actual window-visibility flip
    /// (and, for hide, unmapping the surface) happens in the
    /// `connect_child_revealed_notify` handler wired up in `new()`, off
    /// GTK's own real transition-complete signal rather than a guessed
    /// timeout -- see that handler's comment for why.
    pub fn show(&self) {
        if self.is_animating.get() {
            return;
        }
        // Already targeting revealed -- e.g. a stray double-call to
        // show() -- and nothing left to animate: set_reveal_child(true)
        // below would be a silent no-op (GTK's own setter skips work,
        // and with it the notify, when the value isn't actually
        // changing), which would never fire the
        // connect_child_revealed_notify handler that's the ONLY thing
        // clearing `is_animating`. Skipping the whole call here instead
        // of setting the guard is what stops that handler-that-never-
        // fires from permanently wedging every future show()/hide() open
        // -- confirmed live: this exact race, from balise-autoclose.sh's
        // own two duplicate running instances each independently calling
        // `balise hide` off the same Hyprland event, is what caused
        // Balise to silently stop opening at all mid-session once.
        if self.root_revealer.reveals_child() {
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
        gtk::glib::idle_add_local_once(move || {
            rev.set_reveal_child(true);
        });
    }

    pub fn hide(&self) {
        if self.is_animating.get() {
            return;
        }
        // Same no-op-guard reasoning as show() above, mirrored for the
        // hide direction.
        if !self.root_revealer.reveals_child() {
            return;
        }
        self.is_animating.set(true);

        self.root_revealer.set_reveal_child(false);
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

    // ---- Stack sub-pages (saved networks, hidden network) ---------------
    // Both used to be Revealer overlays popped up on top of whichever tab
    // was showing underneath; now real Stack pages, navigated exactly
    // like show_detail()/leave_detail() above -- same "‹ title" header,
    // same directional slide, same origin-tab bookkeeping via
    // `detail_origin`. leave_detail() itself needed no changes: it
    // already just restores whatever tab `detail_origin` names, with no
    // idea (or need to know) whether the page being left was the endpoint
    // detail page, saved networks, or the hidden-network form.

    /// Both entry points are WiFi-only features, always reached from a
    /// button on the WiFi tab -- origin is always "wifi", not read off
    /// whatever tab happens to be current (there's only one to switch
    /// away from that could reach either of these).
    pub fn show_hidden_network(&self) {
        *self.detail_origin.borrow_mut() = "wifi".to_string();
        self.header.set_detail_mode(Some("Connect to Hidden Network"));
        self.hidden_ssid_entry.set_text("");
        self.hidden_password_entry.set_text("");
        self.stack.set_transition_type(gtk::StackTransitionType::SlideLeftRight);
        self.stack.set_visible_child_name("hidden");
        self.hidden_ssid_entry.grab_focus();
    }

    pub fn show_saved_networks(&self) {
        *self.detail_origin.borrow_mut() = "wifi".to_string();
        self.header.set_detail_mode(Some("Saved Networks"));
        self.stack.set_transition_type(gtk::StackTransitionType::SlideLeftRight);
        self.stack.set_visible_child_name("saved");
    }

    pub fn hidden_ssid_entry(&self) -> &gtk::Entry {
        &self.hidden_ssid_entry
    }

    pub fn hidden_password_entry(&self) -> &gtk::PasswordEntry {
        &self.hidden_password_entry
    }

    pub fn hidden_connect_btn(&self) -> &gtk::Button {
        &self.hidden_connect_btn
    }

    pub fn hidden_cancel_btn(&self) -> &gtk::Button {
        &self.hidden_cancel_btn
    }

    // ---- overlays -------------------------------------------------------

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
