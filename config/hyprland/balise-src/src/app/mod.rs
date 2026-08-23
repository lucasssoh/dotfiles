//! App orchestration: GTK Application, the shared tokio runtime + WiFi
//! NetworkManager instance, the AppEvent event loop, UI callback wiring,
//! and periodic refresh. Adapted from orbit-vendor/src/app/mod.rs,
//! trimmed to WiFi only (no Bluetooth/VPN/wired -- see the project plan's
//! roadmap) and simplified accordingly (Orbit's file juggles four
//! subsystems in one big match; this one juggles one).

use gtk4::gio::ApplicationFlags;
use gtk4::prelude::*;
use gtk4::{glib, Application};
use std::cell::RefCell;
use std::rc::Rc;
use std::sync::{Arc, Mutex};

use crate::config::Config;
use crate::dbus::{AccessPoint, NetworkManager, SavedNetwork};
use crate::ipc::{DaemonCommand, DaemonServer};
use crate::ui::BaliseWindow;

pub enum AppEvent {
    DaemonCommand(DaemonCommand),
    DaemonStarted(DaemonServer),

    WifiPowerState(bool),
    ScanResult(Vec<AccessPoint>),
    SavedResult(Vec<SavedNetwork>),
    ConnectStarted(String),
    DisconnectStarted(String),
    ConnectSuccess,
    ConnectHidden(String, String),
    Error(String),
    Notify(String),
}

pub struct BaliseApp {
    app: Application,
    config: Config,
    is_daemon: bool,
}

impl BaliseApp {
    pub fn new(config: Config) -> Result<Self, glib::Error> {
        Self::new_with_mode(config, false)
    }

    pub fn new_daemon(config: Config) -> Result<Self, glib::Error> {
        Self::new_with_mode(config, true)
    }

    fn new_with_mode(config: Config, is_daemon: bool) -> Result<Self, glib::Error> {
        let app = Application::new(Some("com.balise.app"), ApplicationFlags::empty());
        Ok(Self { app, config, is_daemon })
    }

    pub fn run(&self) -> glib::ExitCode {
        let config = self.config.clone();
        let is_daemon = self.is_daemon;

        self.app.connect_activate(move |app| {
            // SIGTERM/SIGINT -> clean quit, needed for `systemctl --user
            // stop balise` once Phase 5 wires up the systemd unit.
            let app_term = app.clone();
            glib::unix_signal_add_local(15, move || {
                app_term.quit();
                glib::ControlFlow::Break
            });
            let app_int = app.clone();
            glib::unix_signal_add_local(2, move || {
                app_int.quit();
                glib::ControlFlow::Break
            });

            let win = Rc::new(BaliseWindow::new(app, config.clone()));
            let (tx, rx) = async_channel::unbounded::<AppEvent>();
            let is_visible = Rc::new(RefCell::new(!is_daemon));

            // Shared multi-threaded runtime, kept alive for the whole
            // process (see the `_rt_keepalive` binding below). Used both
            // for the daemon's Unix-socket accept setup and for every
            // NetworkManager D-Bus call.
            //
            // DaemonServer::new() uses tokio::net::UnixListener, which
            // needs an active tokio reactor at creation time -- glib's own
            // executor (spawn_future_local) doesn't provide one, hence the
            // background OS thread driving this runtime's block_on. The
            // runtime must then stay alive for as long as the listener is
            // used: dropping it shuts its reactor down, which orphans the
            // listener even though DaemonServer::run() polls it from a
            // SEPARATE dedicated thread/runtime of its own -- confirmed
            // live in Phase 0 (a throwaway per-init-thread runtime produced
            // an infinite "Tokio 1.x context ... being shutdown" error
            // loop the moment that thread's runtime dropped).
            let rt = Arc::new(tokio::runtime::Runtime::new().expect("failed to create tokio runtime"));

            let nm: Arc<Mutex<Option<NetworkManager>>> = Arc::new(Mutex::new(None));

            // Initialization thread: connect to NetworkManager (retried,
            // it may not be up yet at login) and push the first WiFi
            // snapshot, mirroring orbit-vendor/src/app/mod.rs:111-231
            // trimmed to WiFi only.
            {
                let rt_init = rt.clone();
                let nm_init = nm.clone();
                let tx_init = tx.clone();
                std::thread::spawn(move || {
                    let mut instance = None;
                    for _ in 0..5 {
                        match rt_init.block_on(async { NetworkManager::new().await }) {
                            Ok(nm_inst) => {
                                instance = Some(nm_inst);
                                break;
                            }
                            Err(_) => std::thread::sleep(std::time::Duration::from_secs(1)),
                        }
                    }

                    if let Some(ref nm_inst) = instance {
                        if let Ok(enabled) = rt_init.block_on(async { nm_inst.is_wifi_enabled().await }) {
                            let _ = tx_init.send_blocking(AppEvent::WifiPowerState(enabled));
                        }
                        if let Ok(aps) = rt_init.block_on(async { nm_inst.access_points().await }) {
                            let _ = tx_init.send_blocking(AppEvent::ScanResult(aps));
                        }
                        if let Ok(saved) = rt_init.block_on(async { nm_inst.saved_networks().await }) {
                            let _ = tx_init.send_blocking(AppEvent::SavedResult(saved));
                        }
                    }

                    *nm_init.lock().unwrap() = instance;
                });
            }

            if is_daemon {
                let rt_init = rt.clone();
                let tx_init = tx.clone();
                std::thread::spawn(move || match rt_init.block_on(async { DaemonServer::new().await }) {
                    Ok(server) => {
                        let _ = tx_init.send_blocking(AppEvent::DaemonStarted(server));
                    }
                    Err(e) => {
                        eprintln!("balise: failed to start daemon: {}", e);
                        std::process::exit(1);
                    }
                });
            }

            // One-shot GUI mode (no subcommand, `balise` alone): show
            // immediately, matching Orbit's run_gui behavior -- there's no
            // daemon command to trigger it otherwise.
            if !is_daemon {
                win.show();
            }

            let last_refresh = Rc::new(RefCell::new(std::time::Instant::now() - std::time::Duration::from_secs(10)));

            setup_ui_callbacks(win.clone(), nm.clone(), rt.clone(), tx.clone());
            setup_periodic_refresh(win.clone(), nm.clone(), rt.clone(), tx.clone(), is_visible.clone());

            glib::spawn_future_local(async move {
                // Keeps `rt` (and therefore the daemon socket's reactor)
                // alive for as long as this event loop runs -- i.e. the
                // whole process lifetime.
                let _rt_keepalive = rt.clone();

                while let Ok(event) = rx.recv().await {
                    match event {
                        AppEvent::WifiPowerState(enabled) => {
                            win.header().set_power_state(enabled);
                        }
                        AppEvent::ScanResult(aps) => {
                            win.network_list().set_networks(aps);
                        }
                        AppEvent::SavedResult(saved) => {
                            win.saved_list().set_networks(saved);
                        }
                        AppEvent::ConnectStarted(ssid) => {
                            win.network_list().set_connecting_ssid(Some(ssid));
                        }
                        AppEvent::DisconnectStarted(ssid) => {
                            win.network_list().set_disconnecting_ssid(Some(ssid));
                        }
                        AppEvent::ConnectSuccess => {
                            win.network_list().set_connecting_ssid(None);
                            win.network_list().set_disconnecting_ssid(None);
                            win.hide_password_dialog();
                        }
                        AppEvent::ConnectHidden(ssid, password) => {
                            let nm_ref = nm.clone();
                            let rt_ref = rt.clone();
                            let tx_ref = tx.clone();
                            std::thread::spawn(move || {
                                let guard = nm_ref.lock().unwrap();
                                if let Some(ref nm_inst) = *guard {
                                    let devices = rt_ref.block_on(async { nm_inst.wireless_devices().await }).unwrap_or_default();
                                    if let Some(device_path) = devices.first() {
                                        let pwd = if password.is_empty() { None } else { Some(password.as_str()) };
                                        match rt_ref.block_on(async { nm_inst.connect_hidden(&ssid, pwd, device_path).await }) {
                                            Ok(()) => {
                                                let _ = tx_ref.send_blocking(AppEvent::Notify(format!(
                                                    "Connecting to hidden network {}...",
                                                    ssid
                                                )));
                                                std::thread::sleep(std::time::Duration::from_millis(1500));
                                                if let Ok(aps) = rt_ref.block_on(async { nm_inst.access_points().await }) {
                                                    let _ = tx_ref.send_blocking(AppEvent::ScanResult(aps));
                                                }
                                            }
                                            Err(e) => {
                                                let _ = tx_ref.send_blocking(AppEvent::Error(format!("Connect failed: {}", e)));
                                            }
                                        }
                                    }
                                }
                            });
                        }
                        AppEvent::Error(msg) => {
                            win.network_list().set_connecting_ssid(None);
                            win.network_list().set_disconnecting_ssid(None);
                            win.show_error(&msg);
                        }
                        AppEvent::Notify(msg) => {
                            let _ = std::process::Command::new("notify-send")
                                .args(["--app-name=Balise", &msg])
                                .spawn();
                        }
                        AppEvent::DaemonCommand(cmd) => match cmd {
                            DaemonCommand::Show => {
                                win.show();
                                *is_visible.borrow_mut() = true;
                                trigger_refresh(&nm, &rt, &tx, &last_refresh);
                            }
                            DaemonCommand::Hide => {
                                win.hide();
                                *is_visible.borrow_mut() = false;
                            }
                            DaemonCommand::Toggle(position, _tab) => {
                                if *is_visible.borrow() {
                                    win.hide();
                                    *is_visible.borrow_mut() = false;
                                } else {
                                    if let Some(pos) = position {
                                        win.set_position(&pos);
                                    }
                                    win.show();
                                    *is_visible.borrow_mut() = true;
                                    trigger_refresh(&nm, &rt, &tx, &last_refresh);
                                }
                            }
                            DaemonCommand::ReloadTheme => {
                                win.apply_theme();
                            }
                            DaemonCommand::ReloadConfig => {
                                win.reload_config();
                            }
                            DaemonCommand::Quit => {
                                std::process::exit(0);
                            }
                        },
                        AppEvent::DaemonStarted(server) => {
                            let tx_cmd = tx.clone();
                            server.run(move |cmd| {
                                let _ = tx_cmd.send_blocking(AppEvent::DaemonCommand(cmd));
                            });
                        }
                    }
                }
            });
        });

        self.app.run_with_args(&[] as &[&str])
    }
}

/// Full WiFi power/scan/saved refresh, with a 2s cooldown so a stale poll
/// can't race a fresh user action -- adapted from
/// orbit-vendor/src/app/mod.rs's Show/Toggle handlers.
fn trigger_refresh(
    nm: &Arc<Mutex<Option<NetworkManager>>>,
    rt: &Arc<tokio::runtime::Runtime>,
    tx: &async_channel::Sender<AppEvent>,
    last_refresh: &Rc<RefCell<std::time::Instant>>,
) {
    let should_refresh = last_refresh.borrow().elapsed() > std::time::Duration::from_secs(2);
    if !should_refresh {
        return;
    }
    *last_refresh.borrow_mut() = std::time::Instant::now();

    let nm = nm.clone();
    let rt = rt.clone();
    let tx = tx.clone();
    std::thread::spawn(move || {
        let guard = nm.lock().unwrap();
        if let Some(ref nm_inst) = *guard {
            if let Ok(enabled) = rt.block_on(async { nm_inst.is_wifi_enabled().await }) {
                let _ = tx.send_blocking(AppEvent::WifiPowerState(enabled));
            }
            if let Ok(aps) = rt.block_on(async { nm_inst.access_points().await }) {
                let _ = tx.send_blocking(AppEvent::ScanResult(aps));
            }
            if let Ok(saved) = rt.block_on(async { nm_inst.saved_networks().await }) {
                let _ = tx.send_blocking(AppEvent::SavedResult(saved));
            }
        }
    });
}

/// Wires every UI-triggered action to its NetworkManager call, adapted
/// from orbit-vendor/src/app/mod.rs's setup_ui_callbacks (trimmed to
/// WiFi-only -- no tab buttons, no Bluetooth/wired/VPN branches).
fn setup_ui_callbacks(
    win: Rc<BaliseWindow>,
    nm: Arc<Mutex<Option<NetworkManager>>>,
    rt: Arc<tokio::runtime::Runtime>,
    tx: async_channel::Sender<AppEvent>,
) {
    // WiFi radio switch. `is_switching` suppresses a stale poll result
    // from snapping the switch back during the ~2s NetworkManager needs
    // to actually apply the change -- same guard Orbit uses. Arc<Mutex<_>>
    // (not Rc<Cell<_>>): this flag is read/written from the background
    // std::thread::spawn below too, which needs Send.
    let is_switching = Arc::new(Mutex::new(false));
    {
        let nm = nm.clone();
        let rt = rt.clone();
        let tx = tx.clone();
        let header = win.header().clone();
        let is_switching = is_switching.clone();
        win.header().power_switch().connect_active_notify(move |switch| {
            if header.is_programmatic_update() {
                return;
            }
            let enabled = switch.is_active();
            *is_switching.lock().unwrap() = true;

            let nm = nm.clone();
            let rt = rt.clone();
            let tx = tx.clone();
            let is_switching_end = is_switching.clone();
            std::thread::spawn(move || {
                let guard = nm.lock().unwrap();
                if let Some(ref nm_inst) = *guard {
                    let _ = rt.block_on(async { nm_inst.set_wifi_enabled(enabled).await });
                    let _ = tx.send_blocking(AppEvent::WifiPowerState(enabled));
                }
                std::thread::sleep(std::time::Duration::from_secs(2));
                *is_switching_end.lock().unwrap() = false;
            });
        });
    }

    // Scan button.
    {
        let nm = nm.clone();
        let rt = rt.clone();
        let tx = tx.clone();
        win.network_list().scan_button().connect_clicked(move |_| {
            let nm = nm.clone();
            let rt = rt.clone();
            let tx = tx.clone();
            std::thread::spawn(move || {
                let guard = nm.lock().unwrap();
                if let Some(ref nm_inst) = *guard {
                    let _ = rt.block_on(async { nm_inst.request_scan().await });
                    std::thread::sleep(std::time::Duration::from_millis(1500));
                    if let Ok(aps) = rt.block_on(async { nm_inst.access_points().await }) {
                        let _ = tx.send_blocking(AppEvent::ScanResult(aps));
                    }
                }
            });
        });
    }

    // "Saved" button -- show the overlay and refresh its contents.
    {
        let win_saved = win.clone();
        let nm = nm.clone();
        let rt = rt.clone();
        let tx = tx.clone();
        win.network_list().set_on_show_saved(move || {
            win_saved.show_saved_networks();
            let nm = nm.clone();
            let rt = rt.clone();
            let tx = tx.clone();
            std::thread::spawn(move || {
                let guard = nm.lock().unwrap();
                if let Some(ref nm_inst) = *guard {
                    match rt.block_on(async { nm_inst.saved_networks().await }) {
                        Ok(saved) => {
                            let _ = tx.send_blocking(AppEvent::SavedResult(saved));
                        }
                        Err(e) => {
                            let _ = tx.send_blocking(AppEvent::Error(format!("Failed to fetch saved networks: {}", e)));
                        }
                    }
                }
            });
        });
    }

    // Autoconnect switch (per saved-network row).
    {
        let nm = nm.clone();
        let rt = rt.clone();
        let tx = tx.clone();
        win.saved_list().set_on_autoconnect_toggle(move |path, enabled| {
            let nm = nm.clone();
            let rt = rt.clone();
            let tx = tx.clone();
            std::thread::spawn(move || {
                let guard = nm.lock().unwrap();
                if let Some(ref nm_inst) = *guard {
                    match rt.block_on(async { nm_inst.set_autoconnect(&path, enabled).await }) {
                        Ok(()) => {
                            std::thread::sleep(std::time::Duration::from_millis(100));
                            if let Ok(saved) = rt.block_on(async { nm_inst.saved_networks().await }) {
                                let _ = tx.send_blocking(AppEvent::SavedResult(saved));
                            }
                        }
                        Err(e) => {
                            let _ = tx.send_blocking(AppEvent::Error(format!("Failed to update autoconnect: {}", e)));
                            if let Ok(saved) = rt.block_on(async { nm_inst.saved_networks().await }) {
                                let _ = tx.send_blocking(AppEvent::SavedResult(saved));
                            }
                        }
                    }
                }
            });
        });
    }

    // Forget button (per saved-network row).
    {
        let nm = nm.clone();
        let rt = rt.clone();
        let tx = tx.clone();
        win.saved_list().set_on_forget(move |path| {
            let nm = nm.clone();
            let rt = rt.clone();
            let tx = tx.clone();
            std::thread::spawn(move || {
                let guard = nm.lock().unwrap();
                if let Some(ref nm_inst) = *guard {
                    match rt.block_on(async { nm_inst.forget(&path).await }) {
                        Ok(()) => {
                            let _ = tx.send_blocking(AppEvent::Notify("Network forgotten".to_string()));
                            if let Ok(saved) = rt.block_on(async { nm_inst.saved_networks().await }) {
                                let _ = tx.send_blocking(AppEvent::SavedResult(saved));
                            }
                        }
                        Err(e) => {
                            let _ = tx.send_blocking(AppEvent::Error(format!("Forget failed: {}", e)));
                        }
                    }
                }
            });
        });
    }

    // "Hidden" button -- opens the SSID+password overlay, connecting on
    // submit via AppEvent::ConnectHidden (handled in the main event loop).
    {
        let win_hidden = win.clone();
        let tx = tx.clone();
        win.network_list().set_on_connect_hidden(move || {
            let tx = tx.clone();
            win_hidden.show_hidden_dialog(move |data| {
                if let Some((ssid, password)) = data {
                    let _ = tx.send_blocking(AppEvent::ConnectHidden(ssid, password));
                }
            });
        });
    }

    // Connect/Disconnect (per access-point row). Adapted from
    // orbit-vendor/src/app/mod.rs:1004-1110: reuses a saved profile or an
    // open network directly; prompts for a password otherwise.
    {
        let win_connect = win.clone();
        let nm = nm.clone();
        let rt = rt.clone();
        win.network_list().set_on_connect(move |ap: AccessPoint| {
            let nm = nm.clone();
            let rt = rt.clone();
            let tx = tx.clone();
            let device_path = ap.device_path.clone();
            let ssid = ap.ssid.clone();

            if ap.is_connected {
                let _ = tx.send_blocking(AppEvent::DisconnectStarted(ssid.clone()));
                std::thread::spawn(move || {
                    let guard = nm.lock().unwrap();
                    if let Some(ref nm_inst) = *guard {
                        let _ = rt.block_on(async { nm_inst.disconnect(&ssid).await });
                        std::thread::sleep(std::time::Duration::from_millis(1000));
                        let _ = tx.send_blocking(AppEvent::ConnectSuccess);
                        std::thread::sleep(std::time::Duration::from_millis(500));
                        if let Ok(aps) = rt.block_on(async { nm_inst.access_points().await }) {
                            let _ = tx.send_blocking(AppEvent::ScanResult(aps));
                        }
                    }
                });
            } else if !ap.security.needs_password() || ap.is_saved {
                let _ = tx.send_blocking(AppEvent::ConnectStarted(ssid.clone()));
                std::thread::spawn(move || {
                    let guard = nm.lock().unwrap();
                    if let Some(ref nm_inst) = *guard {
                        match rt.block_on(async { nm_inst.connect(&ssid, None, &device_path).await }) {
                            Ok(()) => {
                                std::thread::sleep(std::time::Duration::from_millis(1000));
                                let _ = tx.send_blocking(AppEvent::ConnectSuccess);
                                let _ = tx.send_blocking(AppEvent::Notify(format!("Connected to {}", ssid)));
                                if let Ok(aps) = rt.block_on(async { nm_inst.access_points().await }) {
                                    let _ = tx.send_blocking(AppEvent::ScanResult(aps));
                                }
                            }
                            Err(e) => {
                                let _ = tx.send_blocking(AppEvent::Error(format!("Connect failed: {}", e)));
                            }
                        }
                    }
                });
            } else {
                let ssid_dialog = ssid.clone();
                win_connect.show_password_dialog(&ssid_dialog, move |password| {
                    let Some(pwd) = password else { return };
                    let nm = nm.clone();
                    let rt = rt.clone();
                    let tx = tx.clone();
                    let ssid = ssid.clone();
                    let device_path = device_path.clone();
                    let _ = tx.send_blocking(AppEvent::ConnectStarted(ssid.clone()));
                    std::thread::spawn(move || {
                        let guard = nm.lock().unwrap();
                        if let Some(ref nm_inst) = *guard {
                            match rt.block_on(async { nm_inst.connect(&ssid, Some(&pwd), &device_path).await }) {
                                Ok(()) => {
                                    std::thread::sleep(std::time::Duration::from_millis(1000));
                                    let _ = tx.send_blocking(AppEvent::ConnectSuccess);
                                    let _ = tx.send_blocking(AppEvent::Notify(format!("Connected to {}", ssid)));
                                    if let Ok(aps) = rt.block_on(async { nm_inst.access_points().await }) {
                                        let _ = tx.send_blocking(AppEvent::ScanResult(aps));
                                    }
                                }
                                Err(e) => {
                                    let _ = tx.send_blocking(AppEvent::Error(format!("Connect failed: {}", e)));
                                }
                            }
                        }
                    });
                });
            }
        });
    }
}

/// 5s poll while the panel is visible -- adapted from
/// orbit-vendor/src/app/mod.rs:1426-1479, trimmed to WiFi only (no
/// per-tab branching, since there's only one tab).
fn setup_periodic_refresh(
    win: Rc<BaliseWindow>,
    nm: Arc<Mutex<Option<NetworkManager>>>,
    rt: Arc<tokio::runtime::Runtime>,
    tx: async_channel::Sender<AppEvent>,
    is_visible: Rc<RefCell<bool>>,
) {
    let _ = &win; // reserved for a future per-tab check (see the project plan)
    glib::timeout_add_local(std::time::Duration::from_secs(5), move || {
        if !*is_visible.borrow() {
            return glib::ControlFlow::Continue;
        }
        let nm = nm.clone();
        let rt = rt.clone();
        let tx = tx.clone();
        std::thread::spawn(move || {
            let guard = nm.lock().unwrap();
            if let Some(ref nm_inst) = *guard {
                if let Ok(aps) = rt.block_on(async { nm_inst.access_points().await }) {
                    let _ = tx.send_blocking(AppEvent::ScanResult(aps));
                }
            }
        });
        glib::ControlFlow::Continue
    });
}
