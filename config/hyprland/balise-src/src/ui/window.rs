//! Layer-shell window shell. Phase 0/1 scope: an anchored corner panel
//! (like Orbit, NOT a fullscreen 4-edge overlay like Roue/Prisme -- see
//! the project plan), currently holding just a header placeholder. The
//! WiFi tab (network list, saved list, overlays) slots into `stack` in
//! Phase 1b.

use gtk4::{self as gtk, prelude::*, Application, ApplicationWindow, Orientation, Overlay};
use gtk4_layer_shell::{Edge, KeyboardMode, Layer, LayerShell};
use std::cell::{Cell, RefCell};
use std::rc::Rc;

use crate::config::Config;

pub struct BaliseWindow {
    window: ApplicationWindow,
    root_revealer: gtk::Revealer,
    config: Rc<RefCell<Config>>,
    stack: gtk::Stack,
    fallback_css: gtk::CssProvider,
    user_css: gtk::CssProvider,
    is_animating: Rc<Cell<bool>>,
}

impl BaliseWindow {
    pub fn new(app: &Application, config: Config) -> Self {
        let window = ApplicationWindow::builder()
            .application(app)
            .default_width(340)
            .default_height(420)
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

        let title = gtk::Label::builder()
            .label("Balise")
            .css_classes(["balise-title"])
            .halign(gtk::Align::Start)
            .build();
        let hint = gtk::Label::builder()
            .label("WiFi manager -- under construction")
            .css_classes(["balise-hint"])
            .halign(gtk::Align::Start)
            .build();
        let header = gtk::Box::builder()
            .orientation(Orientation::Vertical)
            .css_classes(["balise-header"])
            .spacing(4)
            .build();
        header.append(&title);
        header.append(&hint);
        panel.append(&header);

        let stack = gtk::Stack::builder().vexpand(true).build();
        panel.append(&stack);

        let overlay = Overlay::new();
        overlay.set_child(Some(&panel));

        let root_revealer = gtk::Revealer::builder()
            .transition_type(parse_revealer_transition(&config.window_transition))
            .transition_duration(config.window_transition_duration)
            .child(&overlay)
            .valign(gtk::Align::Start)
            .build();

        window.set_child(Some(&root_revealer));

        let win = Self {
            window,
            root_revealer,
            config: Rc::new(RefCell::new(config)),
            stack,
            fallback_css,
            user_css,
            is_animating: Rc::new(Cell::new(false)),
        };
        win.apply_position();
        win
    }

    pub fn stack(&self) -> &gtk::Stack {
        &self.stack
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
        // OnDemand while shown -- this is what makes a WiFi password entry
        // typable while the panel is open, without permanently stealing
        // keyboard focus from the rest of the desktop while it's hidden.
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
                // "top-right", and the fallback for anything unrecognized.
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
        // fallback_css never changes at runtime -- kept on the struct only
        // so its CssProvider isn't dropped (which would remove its rules).
        let _ = &self.fallback_css;
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
