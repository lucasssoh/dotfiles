//! Roue — generic native Wayland radial selector (GTK4 + layer-shell), RPG
//! weapon-menu style (press = opens, release or click/Enter = confirms).
//! Replaces the rofi-power.sh/rofi-performance.sh menus, on the same
//! principle as Prisme for the wallpaper selector.
//!
//! A single binary for all wheels: `roue <name>` loads its definition from
//! `~/.config/roue/wheels/<name>.toml` (see config.rs). Adding a new wheel
//! later therefore requires no code change here, just a new TOML file and
//! a trigger (shortcut, waybar click...).
//!
//! The "hold = LB/L1" gesture needs no homemade IPC: `roue <name>
//! --commit`/`--cancel` is a second invocation of the SAME binary, routed
//! to the already-open instance through GApplication's native mechanism
//! (D-Bus activation by application-id, with ApplicationFlags::
//! HANDLES_COMMAND_LINE to receive this second invocation's arguments in
//! the primary process). See keybinds.lua for the press (`bind`) /
//! release (`bind ... { release = true }`) wiring.

mod actions;
mod color;
mod config;
mod icons;
mod theme;
mod wheel;

use gtk4::gdk;
use gtk4::gio::ApplicationFlags;
use gtk4::prelude::*;
use gtk4::{glib, graphene, Application, ApplicationWindow};
use gtk4_layer_shell::{Edge, KeyboardMode, Layer, LayerShell};
use std::cell::RefCell;
use std::collections::HashMap;
use std::rc::Rc;

use wheel::RoueWheel;

/// Wheel keyboard actions -- fixed keyset (no separate keymap.conf file
/// like in Prisme: a single wheel, a deliberately simple interaction, no
/// need for it to be file-reconfigurable here).
#[derive(Clone, Copy)]
enum KeyAction {
    Cancel,
    MoveLeft,
    MoveRight,
    Activate,
    Select(usize),
}

/// Resolves key names (X11/GDK convention, see prisme-src/src/keymap.rs)
/// into actions -- `gdk::Key::from_name` rather than guessing the
/// generated Rust enum identifiers for digit keys.
fn build_keymap() -> HashMap<gdk::Key, KeyAction> {
    let mut m = HashMap::new();
    let mut bind = |names: &[&str], action: KeyAction| {
        for name in names {
            if let Some(key) = gdk::Key::from_name(*name) {
                m.insert(key, action);
            }
        }
    };
    bind(&["Escape"], KeyAction::Cancel);
    bind(&["Left", "h", "H"], KeyAction::MoveLeft);
    bind(&["Right", "l", "L"], KeyAction::MoveRight);
    bind(&["Return", "KP_Enter", "space"], KeyAction::Activate);
    for (i, name) in ["1", "2", "3", "4", "5", "6", "7", "8", "9"].iter().enumerate() {
        bind(&[name], KeyAction::Select(i));
    }
    m
}

/// Cancels without running anything -- from a confirmation sub-menu, just
/// returns to the root wheel; otherwise closes the window. Single shared
/// entry point for Escape and right-click (see their two call sites) so
/// both gestures are guaranteed to stay identical.
fn cancel(wheel: &RoueWheel, window: &ApplicationWindow) {
    if wheel.is_confirming() {
        wheel.cancel_confirm();
    } else {
        window.close();
    }
}

/// State of the single open window (at most one, whatever the wheel name)
/// -- read/written from `connect_command_line`, both for the initial build
/// and to route `--commit`/`--cancel` from a secondary invocation.
type State = Rc<RefCell<Option<(ApplicationWindow, RoueWheel)>>>;

fn main() -> glib::ExitCode {
    // Unlike Prisme (which forces "opengl" -- a carousel of ~25 high-res
    // photos, software rendering clearly choked there): the wheel only
    // draws a few flat polygons and a handful of small icon textures,
    // content far too simple to justify a GL context's memory cost --
    // measured at ~182 MB of stabilized RSS on "opengl" versus ~68 MB on
    // "cairo" (software), with no perceptible smoothness difference given
    // the scene's low complexity. Respects a value already set by the
    // environment (debug, another machine...).
    if std::env::var_os("GSK_RENDERER").is_none() {
        std::env::set_var("GSK_RENDERER", "cairo");
    }

    let wheel_name = std::env::args().nth(1).unwrap_or_else(|| {
        eprintln!("usage: roue <wheel-name> [--commit|--cancel]");
        std::process::exit(1);
    });

    // One application-id per wheel (not a single shared "com.roue.app"):
    // `roue power --commit` must be routed to the already-open `roue
    // power` instance, never to a `powerprofile` wheel that might be
    // running at the same time -- each is an independent GApplication
    // process.
    let app_id = format!("com.roue.{wheel_name}");
    let app = Application::new(Some(&app_id), ApplicationFlags::HANDLES_COMMAND_LINE);

    let state: State = Rc::new(RefCell::new(None));

    {
        let state = state.clone();
        app.connect_command_line(move |app, cmdline| {
            // `cmdline.arguments()` gives the arguments of THIS exact
            // invocation (the primary one at opening, or the one forwarded
            // by D-Bus from a secondary invocation while the wheel is
            // already open) -- never a mix of the two.
            let args: Vec<String> = cmdline
                .arguments()
                .into_iter()
                .map(|a| a.to_string_lossy().into_owned())
                .collect();
            let control = args.iter().skip(2).find_map(|a| match a.as_str() {
                "--commit" => Some(true),
                "--cancel" => Some(false),
                _ => None,
            });

            // Cloned out of the RefCell (Ref/RefMut over GObject wrappers,
            // so just one more refcount) before branching: otherwise the
            // Ref borrowed by `state.borrow()` stays alive until the end
            // of the if/else (including the `else` branch, which needs to
            // borrow `state` mutably via build_ui) -- `already borrowed`
            // panic otherwise, confirmed by running the binary under real
            // conditions.
            let existing = state.borrow().clone();
            if let Some((window, wheel)) = existing {
                match control {
                    // Key release (bindr): confirms the hovered sector (or
                    // cancels, if nothing was aimed at -- see
                    // wheel.rs::activate_hovered). If it was a `confirm`
                    // sector, this just switches to Confirm/Cancel (the
                    // window stays open, activate_hovered returns false).
                    Some(true) => {
                        if wheel.activate_hovered() {
                            window.close();
                        }
                    }
                    Some(false) => {
                        cancel(&wheel, &window);
                    }
                    // A second plain press (not our release) while the
                    // wheel is already open -- just brings the window back
                    // to the foreground (like Prisme, see its doc).
                    None => window.present(),
                }
            } else {
                build_ui(app, &wheel_name, &state);
            }
            0
        });
    }

    app.run()
}

/// Builds the fullscreen layer-shell window and the wheel, then wires up
/// mouse/keyboard. Called once per process (guard in
/// `connect_command_line`).
fn build_ui(app: &Application, wheel_name: &str, state: &State) {
    let cfg = config::load(wheel_name);

    let window = ApplicationWindow::new(app);
    window.add_css_class("background");

    window.init_layer_shell();
    window.set_namespace("roue");
    window.set_layer(Layer::Overlay);
    window.set_keyboard_mode(KeyboardMode::Exclusive);
    window.set_exclusive_zone(-1);
    for edge in [Edge::Top, Edge::Bottom, Edge::Left, Edge::Right] {
        window.set_anchor(edge, true);
    }
    if let Some(display) = gtk4::gdk::Display::default() {
        theme::load(&display, wheel_name);
    }

    // Wheel + side panel block centered as a whole on screen -- horizontal
    // Box WITHOUT hexpand/vexpand (unlike the old vertical layout): as the
    // sole child of a fullscreen window, it gets the full rectangle
    // regardless (standard GtkWindow "bin" behavior), it's its own
    // halign/valign=Center that positions it at ITS natural size (520px
    // wheel + spacing + panel width) in the middle of that rectangle,
    // rather than stretching it.
    let root = gtk4::Box::builder()
        .orientation(gtk4::Orientation::Horizontal)
        .spacing(28)
        .halign(gtk4::Align::Center)
        .valign(gtk4::Align::Center)
        .build();

    // Invisible counterweight, SAME width as the panel (see size_group
    // below) -- without it, it's the [wheel+panel] block AS A WHOLE that
    // gets centered, so the wheel itself ends up shifted left of screen
    // center by exactly half the panel's width. With this counterweight on
    // the opposite side, the wheel becomes the root's geometric middle
    // again, whatever the panel's width (so whatever the text -- "Power"
    // vs "Power profile" don't have the same natural width).
    let counterweight = gtk4::Box::new(gtk4::Orientation::Horizontal, 0);
    root.append(&counterweight);

    let wheel = RoueWheel::new(cfg.segments);
    root.append(&wheel);

    // Side panel -- title + command reminder, aligned on the wheel's
    // vertical center (valign=Center) rather than as a footer.
    let sidebar = gtk4::Box::builder()
        .orientation(gtk4::Orientation::Vertical)
        .spacing(10)
        .valign(gtk4::Align::Center)
        .css_classes(["roue-sidebar"])
        .build();
    let title = gtk4::Label::builder()
        .label(&cfg.title)
        .css_classes(["roue-title"])
        .halign(gtk4::Align::Start)
        .build();
    sidebar.append(&title);
    let hint = gtk4::Label::builder()
        .label("Mouse / ←→  aim\nEnter / click  confirm\nEsc / right-click  cancel")
        .css_classes(["roue-hint"])
        .halign(gtk4::Align::Start)
        .justify(gtk4::Justification::Left)
        .build();
    sidebar.append(&hint);
    root.append(&sidebar);

    // Forces the counterweight to always report the same natural width as
    // the panel (whatever its content) -- this is what makes the wheel's
    // centering exact instead of a hardcoded value that would drift out of
    // sync at the slightest title/font change.
    let width_group = gtk4::SizeGroup::new(gtk4::SizeGroupMode::Horizontal);
    width_group.add_widget(&counterweight);
    width_group.add_widget(&sidebar);

    window.set_child(Some(&root));

    // Clears the shared state the moment the window actually closes
    // (whatever closed it -- Escape, right-click, a confirmed selection,
    // or `--cancel`/`--commit` routed in from a second invocation, see
    // the handlers below and in connect_command_line). Without this,
    // `state` kept its Some((window, wheel)) forever after the first use:
    // a later invocation arriving before the process has fully torn down
    // (e.g. a quick re-click, or the GApplication D-Bus name taking a
    // moment to release) would hit the `existing = Some(...)` branch in
    // connect_command_line and just `.present()` the OLD, already-closed
    // window instead of rebuilding via build_ui() -- which is the only
    // place that re-reads the wheel's TOML. For the audio-output wheel
    // specifically, that TOML is regenerated fresh on every open (see
    // audio.sh's roue-gen), so presenting the stale window meant showing
    // a stale device list -- e.g. a sink that only just appeared, or
    // whose default status just changed -- until enough opens/closes
    // happened to line up with the process actually exiting in between.
    {
        let state_for_close = state.clone();
        window.connect_close_request(move |_| {
            *state_for_close.borrow_mut() = None;
            glib::Propagation::Proceed
        });
    }

    // Mouse hover: attached to the WHOLE WINDOW (not just the wheel
    // widget) -- aiming must not require keeping the cursor inside the
    // wheel's small on-screen disc, only the ANGLE from its center matters
    // (see wheel.rs::hover_from_point, which already ignores distance once
    // past the dead zone). A trip toward the edge of the screen therefore
    // still reads as "aim straight in that direction," like an analog
    // stick pushed past its own range. Coordinates received relative to
    // `window` (the widget the controller is attached to) -- translated
    // into `wheel`'s frame (its own top-left corner) before the call, the
    // only frame hover_from_point knows; nothing else changes, the dead
    // zone and angle calculation stay identical.
    let motion = gtk4::EventControllerMotion::new();
    let wheel_for_motion = wheel.clone();
    let window_for_motion = window.clone();
    motion.connect_motion(move |_, x, y| {
        let point = graphene::Point::new(x as f32, y as f32);
        if let Some(translated) = window_for_motion.compute_point(&wheel_for_motion, &point) {
            wheel_for_motion.hover_from_point(translated.x() as f64, translated.y() as f64);
        }
    });
    window.add_controller(motion);

    // Left click: same reasoning as hover, confirms the hovered sector
    // from anywhere on screen rather than only by clicking right on the
    // wheel. Restricted to the primary button -- WITHOUT this,
    // GestureClick listens to every button by default (button=0), and the
    // right-click below would also end up confirming before even reaching
    // its own controller.
    let click = gtk4::GestureClick::new();
    click.set_button(gdk::BUTTON_PRIMARY);
    let wheel_for_click = wheel.clone();
    let window_for_click = window.clone();
    click.connect_pressed(move |_, _, _, _| {
        if wheel_for_click.activate_hovered() {
            window_for_click.close();
        }
    });
    window.add_controller(click);

    // Right click: mouse equivalent of Escape -- closes the wheel (or
    // returns to the root wheel from a confirmation sub-menu) without ever
    // confirming anything, whatever sector is hovered.
    let right_click = gtk4::GestureClick::new();
    right_click.set_button(gdk::BUTTON_SECONDARY);
    let wheel_for_right_click = wheel.clone();
    let window_for_right_click = window.clone();
    right_click.connect_pressed(move |_, _, _, _| {
        cancel(&wheel_for_right_click, &window_for_right_click);
    });
    window.add_controller(right_click);

    // Only place where an action is actually launched -- never called for
    // a `confirm` sector until it has been confirmed a second time (see
    // wheel.rs::activate_hovered). Closing the window is handled by each
    // caller of activate_hovered() through its return value, not here --
    // this callback only does the side-effect part (launching the
    // action), never the window's lifecycle management.
    wheel.connect_commit(move |seg| {
        actions::run(&seg.action);
    });

    let keymap = build_keymap();
    let key_controller = gtk4::EventControllerKey::new();
    let window_for_key = window.clone();
    let wheel_for_key = wheel.clone();
    key_controller.connect_key_pressed(move |_, key, _, _| {
        let Some(action) = keymap.get(&key).copied() else {
            return glib::Propagation::Proceed;
        };
        match action {
            KeyAction::Cancel => cancel(&wheel_for_key, &window_for_key),
            KeyAction::MoveLeft => wheel_for_key.move_hover(-1),
            KeyAction::MoveRight => wheel_for_key.move_hover(1),
            KeyAction::Activate => {
                if wheel_for_key.activate_hovered() {
                    window_for_key.close();
                }
            }
            KeyAction::Select(i) => wheel_for_key.set_hover_index(i),
        }
        glib::Propagation::Stop
    });
    window.add_controller(key_controller);

    *state.borrow_mut() = Some((window.clone(), wheel));
    window.present();
}
