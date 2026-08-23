//! App orchestration: GTK Application, the shared tokio runtime + WiFi/
//! Bluetooth/Ethernet backends, the AppEvent event loop, UI callback
//! wiring, and periodic refresh. Adapted from orbit-vendor/src/app/mod.rs
//! (no VPN -- see the project plan, dropped for good).

use gtk4::gio::ApplicationFlags;
use gtk4::prelude::*;
use gtk4::{glib, Application};
use std::cell::RefCell;
use std::rc::Rc;
use std::sync::{Arc, Mutex};

use crate::config::Config;
use crate::dbus::{AccessPoint, AgentEvent, BluetoothDevice, BluetoothManager, NetworkManager, SavedNetwork, WiredProfile};
use crate::ipc::{DaemonCommand, DaemonServer};
use crate::ui::device_list::DeviceAction;
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

    // ---- Bluetooth (Phase 3) --------------------------------------------
    BtPowerState(bool),
    BtScanResult(Vec<BluetoothDevice>),
    BtActionStarted(String, DeviceAction),
    BtActionComplete,
    BtPinRequest(String, async_channel::Sender<String>),
    BtPinDisplay(String, String),
    BtPasskeyRequest(String, async_channel::Sender<u32>),
    BtPasskeyDisplay(String, u32, u16),
    BtConfirmRequest(String, u32, async_channel::Sender<bool>),
    BtAuthRequest(String, async_channel::Sender<bool>),
    BtAgentCancel,

    // ---- Ethernet (Phase 2) ----------------------------------------------
    WiredResult(Vec<WiredProfile>),
    WiredConnectStarted(String),
    WiredConnectComplete,

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
            let bt: Arc<Mutex<Option<BluetoothManager>>> = Arc::new(Mutex::new(None));
            let current_tab = Rc::new(RefCell::new("wifi".to_string()));

            // Initialization thread: connect to NetworkManager/BlueZ
            // (retried, they may not be up yet at login) and push the
            // first WiFi + Bluetooth snapshots, mirroring
            // orbit-vendor/src/app/mod.rs:111-231.
            {
                let rt_init = rt.clone();
                let nm_init = nm.clone();
                let bt_init = bt.clone();
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

                    let mut bt_instance = None;
                    for _ in 0..5 {
                        match rt_init.block_on(async { BluetoothManager::new().await }) {
                            Ok(bt_inst) => {
                                bt_instance = Some(bt_inst);
                                break;
                            }
                            Err(_) => std::thread::sleep(std::time::Duration::from_secs(1)),
                        }
                    }

                    if let Some(bt_inst) = bt_instance {
                        if let Ok(powered) = rt_init.block_on(async { bt_inst.is_powered().await }) {
                            let _ = tx_init.send_blocking(AppEvent::BtPowerState(powered));
                        }
                        if let Ok(devices) = rt_init.block_on(async { bt_inst.get_devices().await }) {
                            let _ = tx_init.send_blocking(AppEvent::BtScanResult(devices));
                        }

                        // Register the pairing agent on a CLONE (zbus's
                        // Connection is cheaply Clone and shares the same
                        // underlying object server, so this still
                        // registers against the one real connection) --
                        // forward every AgentEvent onto the main AppEvent
                        // channel. Needs its own tokio runtime handle to
                        // keep zbus's object server alive and responsive
                        // to BlueZ callbacks (see dbus/bluez.rs's doc
                        // comment on register_agent).
                        let (agent_tx, agent_rx) = async_channel::unbounded::<AgentEvent>();
                        let rt_agent = rt_init.clone();
                        let tx_agent = tx_init.clone();
                        let mut bt_agent = bt_inst.clone();
                        std::thread::spawn(move || {
                            if let Err(e) = rt_agent.block_on(async { bt_agent.register_agent(agent_tx).await }) {
                                eprintln!("balise: failed to register Bluetooth agent: {}", e);
                                return;
                            }
                            rt_agent.block_on(async move {
                                while let Ok(event) = agent_rx.recv().await {
                                    match event {
                                        AgentEvent::PinRequest(path, tx) => {
                                            let _ = tx_agent.send_blocking(AppEvent::BtPinRequest(path, tx));
                                        }
                                        AgentEvent::PinDisplay(path, pin) => {
                                            let _ = tx_agent.send_blocking(AppEvent::BtPinDisplay(path, pin));
                                        }
                                        AgentEvent::PasskeyRequest(path, tx) => {
                                            let _ = tx_agent.send_blocking(AppEvent::BtPasskeyRequest(path, tx));
                                        }
                                        AgentEvent::PasskeyDisplay(path, passkey, entered) => {
                                            let _ = tx_agent.send_blocking(AppEvent::BtPasskeyDisplay(path, passkey, entered));
                                        }
                                        AgentEvent::ConfirmRequest(path, passkey, tx) => {
                                            let _ = tx_agent.send_blocking(AppEvent::BtConfirmRequest(path, passkey, tx));
                                        }
                                        AgentEvent::AuthRequest(path, tx) => {
                                            let _ = tx_agent.send_blocking(AppEvent::BtAuthRequest(path, tx));
                                        }
                                        AgentEvent::Cancel => {
                                            let _ = tx_agent.send_blocking(AppEvent::BtAgentCancel);
                                        }
                                    }
                                }
                            });
                        });

                        *bt_init.lock().unwrap() = Some(bt_inst);
                    }
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
            // Shared with the Toggle(_, Some(tab)) daemon command below,
            // so a `balise toggle --tab bluetooth` suppresses a stale
            // poll snapping the radio switch back exactly like a manual
            // tab click does.
            let is_switching = Arc::new(Mutex::new(false));

            setup_ui_callbacks(win.clone(), nm.clone(), bt.clone(), rt.clone(), tx.clone(), current_tab.clone(), is_switching.clone());
            setup_periodic_refresh(win.clone(), nm.clone(), bt.clone(), rt.clone(), tx.clone(), is_visible.clone(), current_tab.clone());

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
                        AppEvent::BtPowerState(enabled) => {
                            win.header().set_power_state(enabled);
                        }
                        AppEvent::BtScanResult(devices) => {
                            win.device_list().set_devices(devices);
                        }
                        AppEvent::BtActionStarted(path, action) => {
                            win.device_list().set_action_state(Some(path), Some(action));
                        }
                        AppEvent::BtActionComplete => {
                            win.device_list().set_action_state(None, None);
                        }
                        AppEvent::BtPinRequest(path, tx) => {
                            let name = win.device_list().get_device_name(&path).unwrap_or_else(|| "Unknown Device".to_string());
                            win.show_bt_pin_request(&name, tx);
                            win.show();
                        }
                        AppEvent::BtPinDisplay(path, pin) => {
                            let name = win.device_list().get_device_name(&path).unwrap_or_else(|| "Unknown Device".to_string());
                            win.show_bt_pin_display(&name, &pin);
                            win.show();
                        }
                        AppEvent::BtPasskeyRequest(path, tx) => {
                            let name = win.device_list().get_device_name(&path).unwrap_or_else(|| "Unknown Device".to_string());
                            win.show_bt_passkey_request(&name, tx);
                            win.show();
                        }
                        AppEvent::BtPasskeyDisplay(path, passkey, _entered) => {
                            let name = win.device_list().get_device_name(&path).unwrap_or_else(|| "Unknown Device".to_string());
                            win.show_bt_passkey_display(&name, passkey);
                            win.show();
                        }
                        AppEvent::BtConfirmRequest(path, passkey, tx) => {
                            let name = win.device_list().get_device_name(&path).unwrap_or_else(|| "Unknown Device".to_string());
                            win.show_bt_confirm_request(&name, passkey, tx);
                            win.show();
                        }
                        AppEvent::BtAuthRequest(path, tx) => {
                            let name = win.device_list().get_device_name(&path).unwrap_or_else(|| "Unknown Device".to_string());
                            win.show_bt_confirm_request(&name, 0, tx);
                            win.show();
                        }
                        AppEvent::BtAgentCancel => {
                            win.cancel_bt_agent();
                        }
                        AppEvent::WiredResult(profiles) => {
                            win.wired_list().set_profiles(profiles);
                        }
                        AppEvent::WiredConnectStarted(device_path) => {
                            win.wired_list().set_connecting(Some(device_path));
                        }
                        AppEvent::WiredConnectComplete => {
                            win.wired_list().set_connecting(None);
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
                            DaemonCommand::Toggle(position, tab) => {
                                if *is_visible.borrow() {
                                    win.hide();
                                    *is_visible.borrow_mut() = false;
                                } else {
                                    if let Some(pos) = position {
                                        win.set_position(&pos);
                                    }
                                    if let Some(ref t) = tab {
                                        activate_tab(&win, &nm, &bt, &rt, &tx, &current_tab, &is_switching, t);
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

/// Switches the visible stack page + header tint, and pushes a fresh
/// power-state/list read for whichever backend just became current --
/// shared by the header's own tab buttons and by `balise toggle --tab
/// <tab>` (DaemonCommand::Toggle), so both paths behave identically.
fn activate_tab(
    win: &Rc<BaliseWindow>,
    nm: &Arc<Mutex<Option<NetworkManager>>>,
    bt: &Arc<Mutex<Option<BluetoothManager>>>,
    rt: &Arc<tokio::runtime::Runtime>,
    tx: &async_channel::Sender<AppEvent>,
    current_tab: &Rc<RefCell<String>>,
    is_switching: &Arc<Mutex<bool>>,
    tab: &str,
) {
    if tab != "wifi" && tab != "bluetooth" && tab != "ethernet" {
        return;
    }
    *current_tab.borrow_mut() = tab.to_string();
    win.stack().set_visible_child_name(tab);
    win.header().set_tab(tab);

    let nm = nm.clone();
    let bt = bt.clone();
    let rt = rt.clone();
    let tx = tx.clone();
    let is_switching = is_switching.clone();
    let tab = tab.to_string();
    std::thread::spawn(move || match tab.as_str() {
        "wifi" => {
            let guard = nm.lock().unwrap();
            if let Some(ref nm_inst) = *guard {
                if let Ok(enabled) = rt.block_on(async { nm_inst.is_wifi_enabled().await }) {
                    if !*is_switching.lock().unwrap() {
                        let _ = tx.send_blocking(AppEvent::WifiPowerState(enabled));
                    }
                }
                if let Ok(aps) = rt.block_on(async { nm_inst.access_points().await }) {
                    let _ = tx.send_blocking(AppEvent::ScanResult(aps));
                }
            }
        }
        "bluetooth" => {
            let guard = bt.lock().unwrap();
            if let Some(ref bt_inst) = *guard {
                if let Ok(enabled) = rt.block_on(async { bt_inst.is_powered().await }) {
                    if !*is_switching.lock().unwrap() {
                        let _ = tx.send_blocking(AppEvent::BtPowerState(enabled));
                    }
                }
                if let Ok(devices) = rt.block_on(async { bt_inst.get_devices().await }) {
                    let _ = tx.send_blocking(AppEvent::BtScanResult(devices));
                }
            }
        }
        "ethernet" => {
            let guard = nm.lock().unwrap();
            if let Some(ref nm_inst) = *guard {
                if let Ok(profiles) = rt.block_on(async { nm_inst.wired_profiles().await }) {
                    let _ = tx.send_blocking(AppEvent::WiredResult(profiles));
                }
            }
        }
        _ => {}
    });
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

/// Wires every UI-triggered action to its backend call, adapted from
/// orbit-vendor/src/app/mod.rs's setup_ui_callbacks (no VPN branch --
/// dropped for good, see the project plan).
fn setup_ui_callbacks(
    win: Rc<BaliseWindow>,
    nm: Arc<Mutex<Option<NetworkManager>>>,
    bt: Arc<Mutex<Option<BluetoothManager>>>,
    rt: Arc<tokio::runtime::Runtime>,
    tx: async_channel::Sender<AppEvent>,
    current_tab: Rc<RefCell<String>>,
    is_switching: Arc<Mutex<bool>>,
) {
    // Radio switch, shared across the WiFi/Bluetooth tabs (Ethernet hides
    // it entirely -- see Header::set_tab). Which backend it drives is
    // decided by `current_tab` at click time. `is_switching` suppresses a
    // stale poll result from snapping the switch back during the ~2s the
    // backend needs to actually apply the change -- same guard Orbit
    // uses. Arc<Mutex<_>> (not Rc<Cell<_>>): this flag is read/written
    // from the background std::thread::spawn below too, which needs Send,
    // and is shared with activate_tab (used by both tab clicks and
    // `balise toggle --tab`, see below).
    {
        let nm = nm.clone();
        let bt = bt.clone();
        let rt = rt.clone();
        let tx = tx.clone();
        let header = win.header().clone();
        let is_switching = is_switching.clone();
        let current_tab = current_tab.clone();
        win.header().power_switch().connect_active_notify(move |switch| {
            if header.is_programmatic_update() {
                return;
            }
            let enabled = switch.is_active();
            *is_switching.lock().unwrap() = true;

            let nm = nm.clone();
            let bt = bt.clone();
            let rt = rt.clone();
            let tx = tx.clone();
            let is_switching_end = is_switching.clone();
            let tab = current_tab.borrow().clone();
            std::thread::spawn(move || {
                if tab == "bluetooth" {
                    let guard = bt.lock().unwrap();
                    if let Some(ref bt_inst) = *guard {
                        match rt.block_on(async { bt_inst.set_powered(enabled).await }) {
                            Ok(()) => {
                                let _ = tx.send_blocking(AppEvent::BtPowerState(enabled));
                            }
                            Err(e) => {
                                let _ = tx.send_blocking(AppEvent::Error(format!("Failed to toggle Bluetooth: {}", e)));
                                if let Ok(actual) = rt.block_on(async { bt_inst.is_powered().await }) {
                                    let _ = tx.send_blocking(AppEvent::BtPowerState(actual));
                                }
                            }
                        }
                    }
                } else {
                    let guard = nm.lock().unwrap();
                    if let Some(ref nm_inst) = *guard {
                        let _ = rt.block_on(async { nm_inst.set_wifi_enabled(enabled).await });
                        let _ = tx.send_blocking(AppEvent::WifiPowerState(enabled));
                    }
                }
                std::thread::sleep(std::time::Duration::from_secs(2));
                *is_switching_end.lock().unwrap() = false;
            });
        });
    }

    // Tab buttons: activate_tab() (below setup_ui_callbacks) does the
    // actual stack/header switch + backend refresh -- shared with
    // `balise toggle --tab <tab>`'s DaemonCommand::Toggle handling.
    {
        let btn = win.header().wifi_tab().clone();
        let win = win.clone();
        let nm = nm.clone();
        let bt = bt.clone();
        let rt = rt.clone();
        let tx = tx.clone();
        let current_tab = current_tab.clone();
        let is_switching = is_switching.clone();
        btn.connect_clicked(move |_| {
            activate_tab(&win, &nm, &bt, &rt, &tx, &current_tab, &is_switching, "wifi");
        });
    }
    {
        let btn = win.header().bluetooth_tab().clone();
        let win = win.clone();
        let nm = nm.clone();
        let bt = bt.clone();
        let rt = rt.clone();
        let tx = tx.clone();
        let current_tab = current_tab.clone();
        let is_switching = is_switching.clone();
        btn.connect_clicked(move |_| {
            activate_tab(&win, &nm, &bt, &rt, &tx, &current_tab, &is_switching, "bluetooth");
        });
    }
    {
        let btn = win.header().ethernet_tab().clone();
        let win = win.clone();
        let nm = nm.clone();
        let bt = bt.clone();
        let rt = rt.clone();
        let tx = tx.clone();
        let current_tab = current_tab.clone();
        let is_switching = is_switching.clone();
        btn.connect_clicked(move |_| {
            activate_tab(&win, &nm, &bt, &rt, &tx, &current_tab, &is_switching, "ethernet");
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
        let tx = tx.clone();
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

    // ---- Bluetooth (Phase 3) ---------------------------------------------

    // Scan button.
    {
        let bt = bt.clone();
        let rt = rt.clone();
        let tx = tx.clone();
        let dev_list = win.device_list().clone();
        win.device_list().scan_button().connect_clicked(move |_| {
            dev_list.show_scanning();
            let bt = bt.clone();
            let rt = rt.clone();
            let tx = tx.clone();
            std::thread::spawn(move || {
                let guard = bt.lock().unwrap();
                if let Some(ref bt_inst) = *guard {
                    let _ = rt.block_on(async { bt_inst.start_discovery().await });
                    std::thread::sleep(std::time::Duration::from_secs(5));
                    let _ = rt.block_on(async { bt_inst.stop_discovery().await });
                    if let Ok(devices) = rt.block_on(async { bt_inst.get_devices().await }) {
                        let _ = tx.send_blocking(AppEvent::BtScanResult(devices));
                    }
                }
            });
        });
    }

    // Connect/Disconnect/Pair/Forget (per device row). Adapted from
    // orbit-vendor/src/app/mod.rs:1234-1262 -- Balise folds "Forget" into
    // the same DeviceAction dispatch instead of a separate callback (see
    // ui/device_list.rs).
    {
        let bt = bt.clone();
        let rt = rt.clone();
        let tx = tx.clone();
        win.device_list().set_on_action(move |path: String, action: DeviceAction| {
            let bt = bt.clone();
            let rt = rt.clone();
            let tx = tx.clone();
            let _ = tx.send_blocking(AppEvent::BtActionStarted(path.clone(), action.clone()));
            std::thread::spawn(move || {
                let guard = bt.lock().unwrap();
                if let Some(ref bt_inst) = *guard {
                    let res = match action {
                        DeviceAction::Connect => rt.block_on(async { bt_inst.connect_device(&path).await }),
                        DeviceAction::Disconnect => rt.block_on(async { bt_inst.disconnect_device(&path).await }),
                        DeviceAction::Pair => rt.block_on(async { bt_inst.pair_device(&path).await }),
                        DeviceAction::Forget => rt.block_on(async { bt_inst.forget_device(&path).await }),
                    };
                    match res {
                        Ok(()) => {
                            let _ = tx.send_blocking(AppEvent::BtActionComplete);
                            if matches!(action, DeviceAction::Forget) {
                                let _ = tx.send_blocking(AppEvent::Notify("Device forgotten".to_string()));
                            }
                            std::thread::sleep(std::time::Duration::from_millis(500));
                            if let Ok(devices) = rt.block_on(async { bt_inst.get_devices().await }) {
                                let _ = tx.send_blocking(AppEvent::BtScanResult(devices));
                            }
                        }
                        Err(e) => {
                            let _ = tx.send_blocking(AppEvent::BtActionComplete);
                            let _ = tx.send_blocking(AppEvent::Error(format!("Bluetooth action failed: {}", e)));
                            if let Ok(devices) = rt.block_on(async { bt_inst.get_devices().await }) {
                                let _ = tx.send_blocking(AppEvent::BtScanResult(devices));
                            }
                        }
                    }
                }
            });
        });
    }

    // Bluetooth pairing-agent overlay's Confirm/Cancel buttons already
    // dispatch to whichever of pin/passkey/confirm callback is set
    // (wired up in ui/window.rs itself, next to where the overlay is
    // built) -- nothing further to wire here.

    // ---- Ethernet (Phase 2) -----------------------------------------------

    // Connect/Disconnect (per wired-device row).
    {
        let nm = nm.clone();
        let rt = rt.clone();
        let tx = tx.clone();
        win.wired_list().set_on_connect(move |profile: WiredProfile| {
            let nm = nm.clone();
            let rt = rt.clone();
            let tx = tx.clone();
            let device_path = profile.device_path.clone();
            let connection_path = profile.connection_path.clone();

            if profile.is_active {
                let _ = tx.send_blocking(AppEvent::WiredConnectStarted(device_path.clone()));
                std::thread::spawn(move || {
                    let guard = nm.lock().unwrap();
                    if let Some(ref nm_inst) = *guard {
                        match rt.block_on(async { nm_inst.deactivate_wired(&device_path).await }) {
                            Ok(()) => {
                                let _ = tx.send_blocking(AppEvent::WiredConnectComplete);
                                if let Ok(profiles) = rt.block_on(async { nm_inst.wired_profiles().await }) {
                                    let _ = tx.send_blocking(AppEvent::WiredResult(profiles));
                                }
                            }
                            Err(e) => {
                                let _ = tx.send_blocking(AppEvent::WiredConnectComplete);
                                let _ = tx.send_blocking(AppEvent::Error(format!("Disconnect failed: {}", e)));
                            }
                        }
                    }
                });
            } else {
                let _ = tx.send_blocking(AppEvent::WiredConnectStarted(device_path.clone()));
                std::thread::spawn(move || {
                    let guard = nm.lock().unwrap();
                    if let Some(ref nm_inst) = *guard {
                        match rt.block_on(async { nm_inst.activate_wired(&connection_path, &device_path).await }) {
                            Ok(()) => {
                                let _ = tx.send_blocking(AppEvent::WiredConnectComplete);
                                let _ = tx.send_blocking(AppEvent::Notify("Ethernet connected".to_string()));
                                if let Ok(profiles) = rt.block_on(async { nm_inst.wired_profiles().await }) {
                                    let _ = tx.send_blocking(AppEvent::WiredResult(profiles));
                                }
                            }
                            Err(e) => {
                                let _ = tx.send_blocking(AppEvent::WiredConnectComplete);
                                let _ = tx.send_blocking(AppEvent::Error(format!("Connect failed: {}", e)));
                            }
                        }
                    }
                });
            }
        });
    }

    // Autoconnect switch (per wired-device row) -- shares
    // NetworkManager::set_autoconnect with the WiFi saved-networks list.
    {
        let nm = nm.clone();
        let rt = rt.clone();
        let tx = tx.clone();
        win.wired_list().set_on_autoconnect_toggle(move |path, enabled| {
            let nm = nm.clone();
            let rt = rt.clone();
            let tx = tx.clone();
            std::thread::spawn(move || {
                let guard = nm.lock().unwrap();
                if let Some(ref nm_inst) = *guard {
                    match rt.block_on(async { nm_inst.set_autoconnect(&path, enabled).await }) {
                        Ok(()) => {
                            std::thread::sleep(std::time::Duration::from_millis(100));
                            if let Ok(profiles) = rt.block_on(async { nm_inst.wired_profiles().await }) {
                                let _ = tx.send_blocking(AppEvent::WiredResult(profiles));
                            }
                        }
                        Err(e) => {
                            let _ = tx.send_blocking(AppEvent::Error(format!("Failed to update autoconnect: {}", e)));
                            if let Ok(profiles) = rt.block_on(async { nm_inst.wired_profiles().await }) {
                                let _ = tx.send_blocking(AppEvent::WiredResult(profiles));
                            }
                        }
                    }
                }
            });
        });
    }
}

/// 5s poll while the panel is visible AND the polled tab is the one
/// actually showing -- adapted from orbit-vendor/src/app/mod.rs:1426-1479.
fn setup_periodic_refresh(
    win: Rc<BaliseWindow>,
    nm: Arc<Mutex<Option<NetworkManager>>>,
    bt: Arc<Mutex<Option<BluetoothManager>>>,
    rt: Arc<tokio::runtime::Runtime>,
    tx: async_channel::Sender<AppEvent>,
    is_visible: Rc<RefCell<bool>>,
    current_tab: Rc<RefCell<String>>,
) {
    let stack = win.stack().clone();
    glib::timeout_add_local(std::time::Duration::from_secs(5), move || {
        if !*is_visible.borrow() {
            return glib::ControlFlow::Continue;
        }
        let tab = current_tab.borrow().clone();
        let current_visible = stack.visible_child_name().map(|s| s.to_string());
        if Some(tab.clone()) != current_visible {
            return glib::ControlFlow::Continue;
        }

        let nm = nm.clone();
        let bt = bt.clone();
        let rt = rt.clone();
        let tx = tx.clone();
        std::thread::spawn(move || {
            if tab == "wifi" {
                let guard = nm.lock().unwrap();
                if let Some(ref nm_inst) = *guard {
                    if let Ok(aps) = rt.block_on(async { nm_inst.access_points().await }) {
                        let _ = tx.send_blocking(AppEvent::ScanResult(aps));
                    }
                }
            } else if tab == "bluetooth" {
                let guard = bt.lock().unwrap();
                if let Some(ref bt_inst) = *guard {
                    if let Ok(devices) = rt.block_on(async { bt_inst.get_devices().await }) {
                        let _ = tx.send_blocking(AppEvent::BtScanResult(devices));
                    }
                }
            } else if tab == "ethernet" {
                let guard = nm.lock().unwrap();
                if let Some(ref nm_inst) = *guard {
                    if let Ok(profiles) = rt.block_on(async { nm_inst.wired_profiles().await }) {
                        let _ = tx.send_blocking(AppEvent::WiredResult(profiles));
                    }
                }
            }
        });
        glib::ControlFlow::Continue
    });
}
