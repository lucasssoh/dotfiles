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
use crate::dbus::{
    AccessPoint, AgentEvent, BluetoothDevice, BluetoothManager, NetworkManager, SavedNetwork, WifiDetails, WiredProfile,
};
use crate::ipc::{ClientCommand, DaemonServer, NightModeState as PushNightModeState, RadioState, ServerPush};
use crate::ui::detail::{DetailAction, DetailTarget};
use crate::ui::device_list::DeviceAction;
use crate::ui::BaliseWindow;

pub enum AppEvent {
    DaemonCommand(ClientCommand),
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

    /// WiFi detail page: the metadata half is fetched off-thread, so
    /// opening the page is a round trip rather than a direct call.
    /// Boxed -- these are much larger than the other variants and would
    /// otherwise set the size of every AppEvent.
    ShowWifiDetail(Box<AccessPoint>, Box<WifiDetails>),
    /// The QML-only equivalent -- just a broadcast, no `win.*` GTK call
    /// (unlike ShowWifiDetail, which also opens the GTK detail page).
    WifiDetailResult(WifiDetails),

    // ---- Ethernet (Phase 2) ----------------------------------------------
    WiredResult(Vec<WiredProfile>),
    WiredConnectStarted(String),
    WiredConnectComplete,

    Error(String),
    Notify(String),

    /// Night mode's marker-file state, read back after toggling it --
    /// see the home tile's own click handler below.
    NightModeState(bool),
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
            // "home" now, matching the Stack's own initial page (used to
            // default to "wifi" back when that was the first tab) --
            // DaemonCommand::Toggle's same-tab check compares an
            // incoming `--tab` against this, and with the old "wifi"
            // default it misfired the very first time Balise was shown
            // (still sitting on the home page) and then toggled to a
            // section: it read as "same tab as current_tab" and closed
            // instead of navigating in.
            let current_tab = Rc::new(RefCell::new("home".to_string()));

            // Mirrors of the same state already pushed to the GTK
            // widgets below (win.home_view().set_wifi_enabled(...) etc.),
            // kept independently so the QML frontend's own commands
            // (ClientCommand::WifiToggle and friends, see the
            // AppEvent::DaemonCommand match) have a "current state" to
            // flip without reaching into a GTK widget for it -- backend
            // state shouldn't depend on GTK still existing (see the
            // project plan: GTK is meant to come out entirely once QML
            // reaches parity, and this is the one place that would have
            // silently kept a GTK dependency otherwise).
            let wifi_enabled = Rc::new(RefCell::new(false));
            let bt_enabled = Rc::new(RefCell::new(false));
            let night_mode_enabled = Rc::new(RefCell::new(false));
            // Set once AppEvent::DaemonStarted fires (daemon mode only --
            // stays None in one-shot GUI mode, where there's no socket to
            // push state over anyway). RefCell<Option<...>> rather than
            // requiring it up front: the broadcaster only exists once the
            // async DaemonServer::new() call in the init thread below
            // actually resolves.
            let broadcaster: Rc<RefCell<Option<tokio::sync::broadcast::Sender<String>>>> = Rc::new(RefCell::new(None));

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
                            win.home_view().set_wifi_enabled(enabled);
                            *wifi_enabled.borrow_mut() = enabled;
                            broadcast_state(&broadcaster, *wifi_enabled.borrow(), *bt_enabled.borrow(), *night_mode_enabled.borrow());
                        }
                        AppEvent::ScanResult(aps) => {
                            let connected_ssid = aps.iter().find(|ap| ap.is_connected).map(|ap| ap.ssid.clone());
                            win.home_view().set_wifi_ssid(connected_ssid);
                            broadcast_wifi_list(&broadcaster, &aps);
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
                            win.home_view().set_bluetooth_enabled(enabled);
                            *bt_enabled.borrow_mut() = enabled;
                            broadcast_state(&broadcaster, *wifi_enabled.borrow(), *bt_enabled.borrow(), *night_mode_enabled.borrow());
                        }
                        AppEvent::BtScanResult(devices) => {
                            let connected_names: Vec<String> = devices.iter().filter(|d| d.is_connected).map(|d| d.name.clone()).collect();
                            win.home_view().set_bluetooth_connected(connected_names);
                            broadcast_bt_list(&broadcaster, &devices);
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
                        AppEvent::ShowWifiDetail(ap, details) => {
                            win.show_detail(DetailTarget::Wifi { ap: *ap, details: *details });
                        }
                        AppEvent::WifiDetailResult(details) => {
                            broadcast_wifi_detail(&broadcaster, &details);
                        }
                        AppEvent::WiredResult(profiles) => {
                            // Same "connected beats cable-present beats
                            // off" priority Ethernet.qml's own state
                            // derivation uses, over the same fields.
                            let state = if profiles.iter().any(|p| p.is_active) {
                                "connected"
                            } else if profiles.iter().any(|p| p.has_carrier) {
                                "on"
                            } else {
                                "off"
                            };
                            let active_name = profiles.iter().find(|p| p.is_active).map(|p| p.name.as_str());
                            win.home_view().set_ethernet_state(state, active_name);
                            broadcast_wired_list(&broadcaster, &profiles);
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
                        AppEvent::NightModeState(enabled) => {
                            win.home_view().set_night_mode(enabled);
                            *night_mode_enabled.borrow_mut() = enabled;
                            broadcast_state(&broadcaster, *wifi_enabled.borrow(), *bt_enabled.borrow(), *night_mode_enabled.borrow());
                        }
                        AppEvent::DaemonCommand(cmd) => match cmd {
                            ClientCommand::Show => {
                                win.show();
                                *is_visible.borrow_mut() = true;
                                trigger_refresh(&nm, &rt, &tx, &last_refresh);
                            }
                            ClientCommand::Hide => {
                                win.hide();
                                *is_visible.borrow_mut() = false;
                            }
                            // ---- home page commands from the QML frontend
                            // (see the project plan) -- same underlying
                            // calls the GTK home tiles' own click handlers
                            // make in setup_ui_callbacks below, just
                            // triggered over the socket instead of a GTK
                            // signal. The resulting WifiPowerState/
                            // BtPowerState/NightModeState event (sent back
                            // by toggle_radio/run_night_mode_toggle
                            // themselves) is what actually updates
                            // wifi_enabled/bt_enabled/night_mode_enabled
                            // and broadcasts -- no need to do either here.
                            ClientCommand::WifiToggle => {
                                let enabled = !*wifi_enabled.borrow();
                                toggle_radio(nm.clone(), bt.clone(), rt.clone(), tx.clone(), is_switching.clone(), "wifi", enabled);
                            }
                            ClientCommand::BtToggle => {
                                let enabled = !*bt_enabled.borrow();
                                toggle_radio(nm.clone(), bt.clone(), rt.clone(), tx.clone(), is_switching.clone(), "bluetooth", enabled);
                            }
                            ClientCommand::NightModeToggle => {
                                run_night_mode_toggle(tx.clone());
                            }
                            ClientCommand::Screenshot => {
                                run_screenshot(win.clone());
                            }
                            ClientCommand::RefreshState => {
                                let nm = nm.clone();
                                let bt = bt.clone();
                                let rt = rt.clone();
                                let tx = tx.clone();
                                std::thread::spawn(move || {
                                    if let Some(ref nm_inst) = *nm.lock().unwrap() {
                                        if let Ok(enabled) = rt.block_on(async { nm_inst.is_wifi_enabled().await }) {
                                            let _ = tx.send_blocking(AppEvent::WifiPowerState(enabled));
                                        }
                                        // The LISTS too, not just the radio
                                        // power flags. Reported: opening
                                        // Balise after a few minutes showed
                                        // an empty "Current network" and a
                                        // WiFi tile claiming nothing was
                                        // connected, and only going down
                                        // into a section and back fixed it.
                                        //
                                        // That is exactly this: the QML home
                                        // page derives its hero card and
                                        // every tile subtitle from the AP /
                                        // wired / device lists (see
                                        // BaliseHome.qml's heroName,
                                        // connectedWifiAp, activeWiredProfile),
                                        // but the only commands that ever
                                        // broadcast those were WifiScan /
                                        // BtScan / EthList -- all of them
                                        // second-level actions. So the home
                                        // page was rendering whatever the
                                        // last visit to a section had left
                                        // behind, and nothing at all on a
                                        // fresh open.
                                        //
                                        // These are plain cached reads, NOT
                                        // scans: no request_scan(), no
                                        // start_discovery(), no sleep. They
                                        // return what NetworkManager/BlueZ
                                        // already know, which is all the
                                        // home page needs -- it asks which
                                        // network is CONNECTED, never what
                                        // else is in range. That is what
                                        // makes this safe to leave on
                                        // BaliseState's own poll rather than
                                        // firing it on open only.
                                        if let Ok(aps) = rt.block_on(async { nm_inst.access_points().await }) {
                                            let _ = tx.send_blocking(AppEvent::ScanResult(aps));
                                        }
                                        if let Ok(profiles) = rt.block_on(async { nm_inst.wired_profiles().await }) {
                                            let _ = tx.send_blocking(AppEvent::WiredResult(profiles));
                                        }
                                    }
                                    if let Some(ref bt_inst) = *bt.lock().unwrap() {
                                        if let Ok(powered) = rt.block_on(async { bt_inst.is_powered().await }) {
                                            let _ = tx.send_blocking(AppEvent::BtPowerState(powered));
                                        }
                                        if let Ok(devices) = rt.block_on(async { bt_inst.get_devices().await }) {
                                            let _ = tx.send_blocking(AppEvent::BtScanResult(devices));
                                        }
                                    }
                                });
                            }
                            // ---- section lists (second slice) -- same
                            // thread bodies as the matching GTK callbacks
                            // in setup_ui_callbacks below (scan button,
                            // set_on_connect/set_on_action/set_on_connect
                            // for wired), just triggered by a JSON command
                            // instead of a GTK signal. Deliberately no
                            // password/pairing support here -- see the
                            // project plan.
                            ClientCommand::WifiScan => {
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
                            }
                            ClientCommand::WifiConnect { ssid, password } => {
                                let nm = nm.clone();
                                let rt = rt.clone();
                                let tx = tx.clone();
                                // Resolve device_path off GTK's own cached
                                // scan list (kept in sync by the same
                                // ScanResult events QML's own list is
                                // populated from) -- falls back to the
                                // first wireless device for a saved-but-
                                // not-currently-scanned network, same
                                // fallback AppEvent::ConnectHidden already
                                // uses.
                                let cached_device_path = win.network_list().get_network(&ssid).map(|ap| ap.device_path);
                                let _ = tx.send_blocking(AppEvent::ConnectStarted(ssid.clone()));
                                std::thread::spawn(move || {
                                    let guard = nm.lock().unwrap();
                                    if let Some(ref nm_inst) = *guard {
                                        let device_path = match cached_device_path {
                                            Some(p) => Some(p),
                                            None => rt
                                                .block_on(async { nm_inst.wireless_devices().await })
                                                .ok()
                                                .and_then(|d| d.into_iter().next()),
                                        };
                                        if let Some(device_path) = device_path {
                                            match rt.block_on(async { nm_inst.connect(&ssid, password.as_deref(), &device_path).await }) {
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
                                    }
                                });
                            }
                            ClientCommand::WifiDisconnect { ssid } => {
                                let nm = nm.clone();
                                let rt = rt.clone();
                                let tx = tx.clone();
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
                            }
                            ClientCommand::BtScan => {
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
                            }
                            ClientCommand::BtConnect { path } => {
                                run_bt_action(bt.clone(), rt.clone(), tx.clone(), path, DeviceAction::Connect);
                            }
                            ClientCommand::BtDisconnect { path } => {
                                run_bt_action(bt.clone(), rt.clone(), tx.clone(), path, DeviceAction::Disconnect);
                            }
                            ClientCommand::EthConnect { connection_path, device_path } => {
                                let nm = nm.clone();
                                let rt = rt.clone();
                                let tx = tx.clone();
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
                            ClientCommand::EthList => {
                                let nm = nm.clone();
                                let rt = rt.clone();
                                let tx = tx.clone();
                                std::thread::spawn(move || {
                                    let guard = nm.lock().unwrap();
                                    if let Some(ref nm_inst) = *guard {
                                        if let Ok(profiles) = rt.block_on(async { nm_inst.wired_profiles().await }) {
                                            let _ = tx.send_blocking(AppEvent::WiredResult(profiles));
                                        }
                                    }
                                });
                            }
                            // ---- detail page (third slice) -- same
                            // underlying dbus/network_manager.rs and
                            // dbus/bluez.rs calls the GTK detail page's
                            // own buttons already make (ui/detail.rs),
                            // just triggered by a JSON command. Every
                            // mutating one re-fetches and re-broadcasts
                            // its own list/detail afterward so the QML
                            // row and detail page both see the result --
                            // same "one event feeds both UIs" pattern as
                            // WifiScan/BtScan/EthList.
                            ClientCommand::WifiDetail { ssid } => {
                                let nm = nm.clone();
                                let rt = rt.clone();
                                let tx = tx.clone();
                                std::thread::spawn(move || {
                                    let guard = nm.lock().unwrap();
                                    if let Some(ref nm_inst) = *guard {
                                        if let Ok(details) = rt.block_on(async { nm_inst.wifi_details(&ssid).await }) {
                                            let _ = tx.send_blocking(AppEvent::WifiDetailResult(details));
                                        }
                                    }
                                });
                            }
                            ClientCommand::WifiForget { settings_path } => {
                                let nm = nm.clone();
                                let rt = rt.clone();
                                let tx = tx.clone();
                                std::thread::spawn(move || {
                                    let guard = nm.lock().unwrap();
                                    if let Some(ref nm_inst) = *guard {
                                        let _ = rt.block_on(async { nm_inst.forget(&settings_path).await });
                                        if let Ok(aps) = rt.block_on(async { nm_inst.access_points().await }) {
                                            let _ = tx.send_blocking(AppEvent::ScanResult(aps));
                                        }
                                    }
                                });
                            }
                            ClientCommand::WifiAutoconnect { ssid, settings_path, autoconnect } => {
                                let nm = nm.clone();
                                let rt = rt.clone();
                                let tx = tx.clone();
                                std::thread::spawn(move || {
                                    let guard = nm.lock().unwrap();
                                    if let Some(ref nm_inst) = *guard {
                                        let _ = rt.block_on(async { nm_inst.set_autoconnect(&settings_path, autoconnect).await });
                                        if let Ok(details) = rt.block_on(async { nm_inst.wifi_details(&ssid).await }) {
                                            let _ = tx.send_blocking(AppEvent::WifiDetailResult(details));
                                        }
                                    }
                                });
                            }
                            ClientCommand::BtForget { path } => {
                                let bt = bt.clone();
                                let rt = rt.clone();
                                let tx = tx.clone();
                                std::thread::spawn(move || {
                                    let guard = bt.lock().unwrap();
                                    if let Some(ref bt_inst) = *guard {
                                        let _ = rt.block_on(async { bt_inst.forget_device(&path).await });
                                        if let Ok(devices) = rt.block_on(async { bt_inst.get_devices().await }) {
                                            let _ = tx.send_blocking(AppEvent::BtScanResult(devices));
                                        }
                                    }
                                });
                            }
                            ClientCommand::BtTrust { path, trusted } => {
                                let bt = bt.clone();
                                let rt = rt.clone();
                                let tx = tx.clone();
                                std::thread::spawn(move || {
                                    let guard = bt.lock().unwrap();
                                    if let Some(ref bt_inst) = *guard {
                                        let _ = rt.block_on(async { bt_inst.set_trusted(&path, trusted).await });
                                        if let Ok(devices) = rt.block_on(async { bt_inst.get_devices().await }) {
                                            let _ = tx.send_blocking(AppEvent::BtScanResult(devices));
                                        }
                                    }
                                });
                            }
                            ClientCommand::EthAutoconnect { connection_path, autoconnect } => {
                                let nm = nm.clone();
                                let rt = rt.clone();
                                let tx = tx.clone();
                                std::thread::spawn(move || {
                                    let guard = nm.lock().unwrap();
                                    if let Some(ref nm_inst) = *guard {
                                        let _ = rt.block_on(async { nm_inst.set_autoconnect(&connection_path, autoconnect).await });
                                        if let Ok(profiles) = rt.block_on(async { nm_inst.wired_profiles().await }) {
                                            let _ = tx.send_blocking(AppEvent::WiredResult(profiles));
                                        }
                                    }
                                });
                            }
                            ClientCommand::EthDisconnect { device_path } => {
                                let nm = nm.clone();
                                let rt = rt.clone();
                                let tx = tx.clone();
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
                            }
                            ClientCommand::Toggle { position, tab } => {
                                if *is_visible.borrow() {
                                    // Already open: a DIFFERENT tab was
                                    // requested (e.g. BT is showing and the
                                    // bar's WiFi icon was clicked) means
                                    // switch to it and stay open, matching
                                    // a normal tab click -- it must NOT
                                    // read as "toggle this icon off" just
                                    // because Balise happened to be open on
                                    // something else. Only the tab already
                                    // showing (or no tab at all, e.g. a
                                    // bare `balise toggle`) still closes
                                    // the panel.
                                    let same_tab = tab.as_deref().map(|t| t == current_tab.borrow().as_str()).unwrap_or(true);
                                    if same_tab {
                                        win.hide();
                                        *is_visible.borrow_mut() = false;
                                    } else {
                                        if let Some(pos) = position {
                                            win.set_position(&pos);
                                        }
                                        if let Some(ref t) = tab {
                                            activate_tab(&win, &nm, &bt, &rt, &tx, &current_tab, &is_switching, t);
                                        }
                                    }
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
                            ClientCommand::ReloadTheme => {
                                win.apply_theme();
                            }
                            ClientCommand::ReloadConfig => {
                                win.reload_config();
                            }
                            ClientCommand::Quit => {
                                std::process::exit(0);
                            }
                        },
                        AppEvent::DaemonStarted(server) => {
                            *broadcaster.borrow_mut() = Some(server.broadcaster());
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

/// Fetches the WiFi metadata half off-thread, then opens the detail
/// page through the event loop. Shared by the network row's gear and
/// the saved-networks overlay's gear.
fn spawn_wifi_detail(
    nm: &Arc<Mutex<Option<NetworkManager>>>,
    rt: &Arc<tokio::runtime::Runtime>,
    tx: &async_channel::Sender<AppEvent>,
    ap: AccessPoint,
) {
    let nm = nm.clone();
    let rt = rt.clone();
    let tx = tx.clone();
    std::thread::spawn(move || {
        let guard = nm.lock().unwrap();
        if let Some(ref nm_inst) = *guard {
            let details = rt.block_on(async { nm_inst.wifi_details(&ap.ssid).await }).unwrap_or_default();
            let _ = tx.send_blocking(AppEvent::ShowWifiDetail(Box::new(ap), Box::new(details)));
        }
    });
}

/// Serializes a full `ServerPush::State` from the three tracked booleans
/// and sends it to every connected client (QML frontend included) --
/// called after each of WifiPowerState/BtPowerState/NightModeState
/// updates the corresponding tracked value, so it always reflects
/// whichever ONE thing actually just changed plus the other two's
/// last-known values (the push itself carries all three every time,
/// there's no partial/delta message). A no-op (not an error) when
/// `broadcaster` is still None -- either GUI mode (no daemon, no socket)
/// or the brief window during daemon startup before DaemonServer::new()
/// has resolved.
fn broadcast_state(
    broadcaster: &Rc<RefCell<Option<tokio::sync::broadcast::Sender<String>>>>,
    wifi_enabled: bool,
    bt_enabled: bool,
    night_mode_enabled: bool,
) {
    if let Some(tx) = broadcaster.borrow().as_ref() {
        let push = ServerPush::State {
            wifi: RadioState { enabled: wifi_enabled },
            bluetooth: RadioState { enabled: bt_enabled },
            night_mode: PushNightModeState { active: night_mode_enabled },
        };
        // Err here only means "no subscribers currently connected", not
        // a real failure -- nothing to log, the next state change tries
        // again.
        let _ = tx.send(push.to_line());
    }
}

/// Same `broadcaster` plumbing as `broadcast_state` above, but for the
/// WiFi/Bluetooth/Ethernet section lists (second slice, see the project
/// plan) -- separate pushes rather than folded into `ServerPush::State`,
/// so an unrelated radio toggle never re-serializes a whole AP/device/
/// profile list. Called right next to the existing `win.*_list().
/// set_*(...)` GTK calls in the matching `AppEvent::ScanResult`/
/// `BtScanResult`/`WiredResult` arms below -- same event, same data,
/// just also handed to any QML client.
fn broadcast_wifi_list(broadcaster: &Rc<RefCell<Option<tokio::sync::broadcast::Sender<String>>>>, access_points: &[AccessPoint]) {
    if let Some(tx) = broadcaster.borrow().as_ref() {
        let push = ServerPush::WifiList { access_points: access_points.to_vec() };
        let _ = tx.send(push.to_line());
    }
}

fn broadcast_bt_list(broadcaster: &Rc<RefCell<Option<tokio::sync::broadcast::Sender<String>>>>, devices: &[BluetoothDevice]) {
    if let Some(tx) = broadcaster.borrow().as_ref() {
        let push = ServerPush::BluetoothList { devices: devices.to_vec() };
        let _ = tx.send(push.to_line());
    }
}

fn broadcast_wired_list(broadcaster: &Rc<RefCell<Option<tokio::sync::broadcast::Sender<String>>>>, profiles: &[WiredProfile]) {
    if let Some(tx) = broadcaster.borrow().as_ref() {
        let push = ServerPush::WiredList { profiles: profiles.to_vec() };
        let _ = tx.send(push.to_line());
    }
}

fn broadcast_wifi_detail(broadcaster: &Rc<RefCell<Option<tokio::sync::broadcast::Sender<String>>>>, details: &crate::dbus::WifiDetails) {
    if let Some(tx) = broadcaster.borrow().as_ref() {
        let push = ServerPush::WifiDetail { details: details.clone() };
        let _ = tx.send(push.to_line());
    }
}

/// Runs `toggle-night-mode.sh` and reports the resulting marker-file
/// state back through `tx` -- shared by the home tile's own click
/// handler and `ClientCommand::NightModeToggle` (the QML frontend's
/// equivalent, see the project plan), so both trigger the exact same
/// script/state-readback logic.
fn run_night_mode_toggle(tx: async_channel::Sender<AppEvent>) {
    std::thread::spawn(move || {
        let _ = std::process::Command::new("bash")
            .arg("-c")
            .arg("$HOME/.config/hypr/scripts/toggle-night-mode.sh")
            .status();
        let enabled = std::path::Path::new(&format!("{}/.cache/hypr-night-mode", std::env::var("HOME").unwrap_or_default())).exists();
        let _ = tx.send_blocking(AppEvent::NightModeState(enabled));
    });
}

/// Hides Balise then fires the region-capture pipeline -- shared by the
/// home tile's own click handler and `ClientCommand::Screenshot` (the
/// QML frontend's equivalent). Same capture pipeline as the existing
/// Super+Shift+S keybind (hypr/keybinds.lua), not a second one; the
/// short delay is for the close animation to actually finish before
/// `slurp`'s own region selection starts, so it doesn't capture over
/// Balise itself.
fn run_screenshot(win: Rc<BaliseWindow>) {
    win.hide();
    glib::timeout_add_local_once(std::time::Duration::from_millis(200), move || {
        let _ = std::process::Command::new("bash")
            .arg("-c")
            .arg(r#"grim -g "$(slurp)" - | satty --filename - --fullscreen --output-filename - | wl-copy"#)
            .spawn();
    });
}

/// Connect/Disconnect for one Bluetooth device -- shared shape with
/// `set_on_action`'s own dispatch in setup_ui_callbacks below, trimmed to
/// just these two actions (`ClientCommand::BtConnect`/`BtDisconnect`
/// deliberately never pass `DeviceAction::Pair`/`Forget` here -- pairing
/// is a separate later slice, see the project plan).
fn run_bt_action(
    bt: Arc<Mutex<Option<BluetoothManager>>>,
    rt: Arc<tokio::runtime::Runtime>,
    tx: async_channel::Sender<AppEvent>,
    path: String,
    action: DeviceAction,
) {
    let _ = tx.send_blocking(AppEvent::BtActionStarted(path.clone(), action.clone()));
    std::thread::spawn(move || {
        let guard = bt.lock().unwrap();
        if let Some(ref bt_inst) = *guard {
            let res = match action {
                DeviceAction::Connect => rt.block_on(async { bt_inst.connect_device(&path).await }),
                DeviceAction::Disconnect => rt.block_on(async { bt_inst.disconnect_device(&path).await }),
                DeviceAction::Pair | DeviceAction::Forget => return,
            };
            match res {
                Ok(()) => {
                    let _ = tx.send_blocking(AppEvent::BtActionComplete);
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
}

/// Applies a WiFi/Bluetooth radio on/off change and reports the result
/// back through `tx` -- shared by the section header's own radio switch
/// and the home tiles' left-click toggle (see setup_ui_callbacks), so
/// both paths behave identically instead of drifting apart over time.
/// `is_switching` is set here (not by the caller): every caller needs
/// the exact same set-true-before/clear-false-after-2s shape around the
/// actual backend call, so there's no reason to make each one repeat it.
fn toggle_radio(
    nm: Arc<Mutex<Option<NetworkManager>>>,
    bt: Arc<Mutex<Option<BluetoothManager>>>,
    rt: Arc<tokio::runtime::Runtime>,
    tx: async_channel::Sender<AppEvent>,
    is_switching: Arc<Mutex<bool>>,
    which: &str,
    enabled: bool,
) {
    *is_switching.lock().unwrap() = true;
    let is_switching_end = is_switching.clone();
    let which = which.to_string();
    std::thread::spawn(move || {
        if which == "bluetooth" {
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
    // Recorded even for "home" (and anything else unrecognized), before
    // the early return below -- DaemonCommand::Toggle's same-tab check
    // compares an incoming `--tab` against this, and it needs to
    // correctly read "home" back after a `leave_detail()` call passes
    // "home" in here (the back button's own handler, and every
    // destructive DetailAction that leaves the detail page early, all do
    // this) or a stray toggle right after going back to home would
    // misfire as "same tab as before, close" instead of navigating into
    // a section.
    *current_tab.borrow_mut() = tab.to_string();

    if tab != "wifi" && tab != "bluetooth" && tab != "ethernet" {
        return;
    }
    win.show_tab(tab);

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
            let which = if current_tab.borrow().as_str() == "bluetooth" { "bluetooth" } else { "wifi" };
            toggle_radio(nm.clone(), bt.clone(), rt.clone(), tx.clone(), is_switching.clone(), which, enabled);
        });
    }

    // Bottom close bar -- "click anywhere else" itself is handled outside
    // this app entirely, by hypr/scripts/balise-autoclose.sh (Hyprland's
    // `activewindow` event -> `balise hide`, already running); this is
    // just the one genuinely new, explicit close affordance. Routed
    // through `tx` as the same ClientCommand::Hide that script's `balise
    // hide` sends, rather than calling win.hide() directly, so
    // `is_visible` stays in sync the same way every other close path does.
    {
        let tx = tx.clone();
        win.close_bar().connect_clicked(move |_| {
            let _ = tx.send_blocking(AppEvent::DaemonCommand(ClientCommand::Hide));
        });
    }

    // Home tiles -- WiFi/Bluetooth: left click (GtkButton's own
    // `clicked`, primary button + keyboard activation) toggles the radio
    // in place via the same toggle_radio() the section header's own
    // switch uses; right click (a secondary-button GestureClick, added
    // here since the button itself only reacts to primary) opens the
    // section, same activate_tab() plumbing the old tab buttons used.
    // Asked for explicitly over a gear button: "pas de bouton
    // d'engrenage mais clic droit". Ethernet has no radio-enable concept,
    // so its tile keeps the old single-purpose click = navigate.
    {
        let win_wifi = win.clone();
        let nm = nm.clone();
        let bt = bt.clone();
        let rt = rt.clone();
        let tx = tx.clone();
        let is_switching = is_switching.clone();
        win.home_view().wifi_tile().connect_clicked(move |_| {
            let enabled = !win_wifi.home_view().wifi_enabled();
            toggle_radio(nm.clone(), bt.clone(), rt.clone(), tx.clone(), is_switching.clone(), "wifi", enabled);
        });
    }
    {
        let win_wifi = win.clone();
        let nm = nm.clone();
        let bt = bt.clone();
        let rt = rt.clone();
        let tx = tx.clone();
        let current_tab = current_tab.clone();
        let is_switching = is_switching.clone();
        let click = gtk4::GestureClick::new();
        click.set_button(gtk4::gdk::BUTTON_SECONDARY);
        click.connect_pressed(move |gesture, _, _, _| {
            gesture.set_state(gtk4::EventSequenceState::Claimed);
            activate_tab(&win_wifi, &nm, &bt, &rt, &tx, &current_tab, &is_switching, "wifi");
        });
        win.home_view().wifi_tile().add_controller(click);
    }
    {
        let win_bt = win.clone();
        let nm = nm.clone();
        let bt = bt.clone();
        let rt = rt.clone();
        let tx = tx.clone();
        let is_switching = is_switching.clone();
        win.home_view().bluetooth_tile().connect_clicked(move |_| {
            let enabled = !win_bt.home_view().bluetooth_enabled();
            toggle_radio(nm.clone(), bt.clone(), rt.clone(), tx.clone(), is_switching.clone(), "bluetooth", enabled);
        });
    }
    {
        let win_bt = win.clone();
        let nm = nm.clone();
        let bt = bt.clone();
        let rt = rt.clone();
        let tx = tx.clone();
        let current_tab = current_tab.clone();
        let is_switching = is_switching.clone();
        let click = gtk4::GestureClick::new();
        click.set_button(gtk4::gdk::BUTTON_SECONDARY);
        click.connect_pressed(move |gesture, _, _, _| {
            gesture.set_state(gtk4::EventSequenceState::Claimed);
            activate_tab(&win_bt, &nm, &bt, &rt, &tx, &current_tab, &is_switching, "bluetooth");
        });
        win.home_view().bluetooth_tile().add_controller(click);
    }
    {
        let btn = win.home_view().ethernet_tile().clone();
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

    // Airplane Mode tile -- no OS-level single toggle to call (see
    // ui/home.rs's own header comment), just both radios' existing
    // toggle_radio() calls fired together. Reads current state off
    // HomeView the same way the WiFi/Bluetooth tiles' own left-click
    // toggle does: "active" (both off) flips both on, anything else
    // flips both off, regardless of which one was already off.
    {
        let win_air = win.clone();
        let nm = nm.clone();
        let bt = bt.clone();
        let rt = rt.clone();
        let tx = tx.clone();
        let is_switching = is_switching.clone();
        win.home_view().airplane_mode_tile().connect_clicked(move |_| {
            let currently_active = !win_air.home_view().wifi_enabled() && !win_air.home_view().bluetooth_enabled();
            let enable_radios = currently_active;
            toggle_radio(nm.clone(), bt.clone(), rt.clone(), tx.clone(), is_switching.clone(), "wifi", enable_radios);
            toggle_radio(nm.clone(), bt.clone(), rt.clone(), tx.clone(), is_switching.clone(), "bluetooth", enable_radios);
        });
    }

    // Night mode tile -- direct action, no page of its own. Factored out
    // (run_night_mode_toggle) so ClientCommand::NightModeToggle -- the
    // QML frontend's equivalent, see the project plan -- runs the exact
    // same logic instead of a second copy.
    {
        let tx = tx.clone();
        win.home_view().night_tile().connect_clicked(move |_| {
            run_night_mode_toggle(tx.clone());
        });
    }

    // Screenshot tile -- direct action. Factored out (run_screenshot) for
    // the same reason as night mode above.
    {
        let win_shot = win.clone();
        win.home_view().screenshot_tile().connect_clicked(move |_| {
            run_screenshot(win_shot.clone());
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

    // The saved-network row's Forget button is gone (no destructive
    // buttons in lists any more) -- its gear opens the shared detail
    // page instead, where Forget lives. A saved network is not
    // necessarily in range, so fall back to a synthetic AccessPoint
    // when the last scan didn't see it.
    {
        let win_saved_detail = win.clone();
        let nm = nm.clone();
        let rt = rt.clone();
        let tx = tx.clone();
        win.saved_list().set_on_show_detail(move |ssid: String| {
            let ap = win_saved_detail.network_list().get_network(&ssid).unwrap_or_else(|| AccessPoint {
                ssid: ssid.clone(),
                is_saved: true,
                ..Default::default()
            });
            spawn_wifi_detail(&nm, &rt, &tx, ap);
        });
    }

    // "Hidden" button -- navigates to the hidden-network Stack page (see
    // ui/window.rs's show_hidden_network()). Connect/Cancel are wired
    // below, once, rather than re-registered on every open the way the
    // old overlay-based version's Connect handler used to be (a real
    // leaked-handler bug -- see the history note on window.rs's
    // connect_child_revealed_notify wiring).
    {
        let win_hidden = win.clone();
        win.network_list().set_on_connect_hidden(move || {
            win_hidden.show_hidden_network();
        });
    }

    // Hidden-network page: Connect submits via the same
    // AppEvent::ConnectHidden the old overlay's Connect button sent, then
    // leaves the page the same way the detail page's back button does;
    // Cancel just leaves it. Both need `leave_detail()` (a `&self`
    // method), so they're wired here rather than in window.rs's
    // constructor, where `self`/`win` don't exist yet.
    {
        let win_hidden = win.clone();
        let nm = nm.clone();
        let bt = bt.clone();
        let rt = rt.clone();
        let tx = tx.clone();
        let current_tab = current_tab.clone();
        let is_switching = is_switching.clone();
        win.hidden_connect_btn().connect_clicked(move |_| {
            let ssid = win_hidden.hidden_ssid_entry().text().to_string();
            let password = win_hidden.hidden_password_entry().text().to_string();
            let origin = win_hidden.leave_detail();
            activate_tab(&win_hidden, &nm, &bt, &rt, &tx, &current_tab, &is_switching, &origin);
            let _ = tx.send_blocking(AppEvent::ConnectHidden(ssid, password));
        });
    }
    {
        let win_hidden = win.clone();
        let nm = nm.clone();
        let bt = bt.clone();
        let rt = rt.clone();
        let tx = tx.clone();
        let current_tab = current_tab.clone();
        let is_switching = is_switching.clone();
        win.hidden_cancel_btn().connect_clicked(move |_| {
            let origin = win_hidden.leave_detail();
            activate_tab(&win_hidden, &nm, &bt, &rt, &tx, &current_tab, &is_switching, &origin);
        });
    }

    // Connect/Disconnect (per access-point row). Adapted from
    // orbit-vendor/src/app/mod.rs:1004-1110: reuses a saved profile or an
    // open network directly; prompts for a password otherwise.
    {
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
            }
            // The secured/unsaved case never reaches here any more:
            // network_list expands its own inline password form and
            // reports back through `set_on_connect_password` below.
        });
    }

    // Inline password form's Connect (ui/network_list.rs) -- the
    // secured/unsaved path that used to go through the bottom overlay.
    {
        let nm = nm.clone();
        let rt = rt.clone();
        let tx = tx.clone();
        win.network_list().set_on_connect_password(move |ap: AccessPoint, password: String| {
            let nm = nm.clone();
            let rt = rt.clone();
            let tx = tx.clone();
            let ssid = ap.ssid.clone();
            let device_path = ap.device_path.clone();
            let _ = tx.send_blocking(AppEvent::ConnectStarted(ssid.clone()));
            std::thread::spawn(move || {
                let guard = nm.lock().unwrap();
                if let Some(ref nm_inst) = *guard {
                    match rt.block_on(async { nm_inst.connect(&ssid, Some(&password), &device_path).await }) {
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

    // ---- detail page navigation ------------------------------------------

    // WiFi gear: the metadata half needs a D-Bus round trip, so this
    // hops through AppEvent::ShowWifiDetail rather than opening directly.
    {
        let nm = nm.clone();
        let rt = rt.clone();
        let tx = tx.clone();
        win.network_list().set_on_show_detail(move |ap: AccessPoint| {
            spawn_wifi_detail(&nm, &rt, &tx, ap);
        });
    }

    // Bluetooth gear: BlueZ's GetManagedObjects already gave us every
    // field, so this opens straight from the cached list -- no round
    // trip, no event hop.
    {
        let win_detail = win.clone();
        win.device_list().set_on_show_detail(move |path: String| {
            if let Some(device) = win_detail.device_list().get_device(&path) {
                win_detail.show_detail(DetailTarget::Bluetooth(device));
            }
        });
    }

    // Ethernet gear: same, the row already carries the full profile.
    {
        let win_detail = win.clone();
        win.wired_list().set_on_show_detail(move |profile: WiredProfile| {
            win_detail.show_detail(DetailTarget::Ethernet(profile));
        });
    }

    // Back button: restore the tab bar, then resync whatever tab we
    // landed back on (its data may have changed while we were away --
    // a Forget or a trust toggle almost always did change it).
    {
        let win_back = win.clone();
        let nm = nm.clone();
        let bt = bt.clone();
        let rt = rt.clone();
        let tx = tx.clone();
        let current_tab = current_tab.clone();
        let is_switching = is_switching.clone();
        win.header().back_button().connect_clicked(move |_| {
            let origin = win_back.leave_detail();
            activate_tab(&win_back, &nm, &bt, &rt, &tx, &current_tab, &is_switching, &origin);
        });
    }

    // Detail page actions. Everything destructive or secondary now
    // arrives here rather than from a row. Each arm re-uses the same
    // AppEvents the lists do, so results land in the UI identically.
    {
        let win_action = win.clone();
        let nm = nm.clone();
        let bt = bt.clone();
        let rt = rt.clone();
        let tx = tx.clone();
        let current_tab = current_tab.clone();
        let is_switching = is_switching.clone();
        win.detail_view().set_on_action(move |action: DetailAction| {
            let nm = nm.clone();
            let bt = bt.clone();
            let rt = rt.clone();
            let tx = tx.clone();

            match action {
                DetailAction::WifiDisconnect(ssid) => {
                    let _ = tx.send_blocking(AppEvent::DisconnectStarted(ssid.clone()));
                    std::thread::spawn(move || {
                        let guard = nm.lock().unwrap();
                        if let Some(ref nm_inst) = *guard {
                            let _ = rt.block_on(async { nm_inst.disconnect(&ssid).await });
                            std::thread::sleep(std::time::Duration::from_millis(1000));
                            let _ = tx.send_blocking(AppEvent::ConnectSuccess);
                            if let Ok(aps) = rt.block_on(async { nm_inst.access_points().await }) {
                                let _ = tx.send_blocking(AppEvent::ScanResult(aps));
                            }
                        }
                    });
                }
                DetailAction::WifiForget(path) => {
                    // Forgetting removes the very thing this page is
                    // about, so leave it first rather than sitting on a
                    // page describing a profile that no longer exists.
                    let origin = win_action.leave_detail();
                    activate_tab(&win_action, &nm, &bt, &rt, &tx, &current_tab, &is_switching, &origin);
                    std::thread::spawn(move || {
                        let guard = nm.lock().unwrap();
                        if let Some(ref nm_inst) = *guard {
                            match rt.block_on(async { nm_inst.forget(&path).await }) {
                                Ok(()) => {
                                    let _ = tx.send_blocking(AppEvent::Notify("Network forgotten".to_string()));
                                    if let Ok(aps) = rt.block_on(async { nm_inst.access_points().await }) {
                                        let _ = tx.send_blocking(AppEvent::ScanResult(aps));
                                    }
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
                }
                DetailAction::WifiAutoconnect(path, on) => {
                    std::thread::spawn(move || {
                        let guard = nm.lock().unwrap();
                        if let Some(ref nm_inst) = *guard {
                            if let Err(e) = rt.block_on(async { nm_inst.set_autoconnect(&path, on).await }) {
                                let _ = tx.send_blocking(AppEvent::Error(format!("Failed to update autoconnect: {}", e)));
                            }
                            if let Ok(saved) = rt.block_on(async { nm_inst.saved_networks().await }) {
                                let _ = tx.send_blocking(AppEvent::SavedResult(saved));
                            }
                        }
                    });
                }
                DetailAction::Bt(path, bt_action) => {
                    // Forget destroys this page's subject, same as WiFi.
                    if matches!(bt_action, DeviceAction::Forget) {
                        let origin = win_action.leave_detail();
                        activate_tab(&win_action, &nm, &bt, &rt, &tx, &current_tab, &is_switching, &origin);
                    }
                    let _ = tx.send_blocking(AppEvent::BtActionStarted(path.clone(), bt_action.clone()));
                    std::thread::spawn(move || {
                        let guard = bt.lock().unwrap();
                        if let Some(ref bt_inst) = *guard {
                            let res = match bt_action {
                                DeviceAction::Connect => rt.block_on(async { bt_inst.connect_device(&path).await }),
                                DeviceAction::Disconnect => rt.block_on(async { bt_inst.disconnect_device(&path).await }),
                                DeviceAction::Pair => rt.block_on(async { bt_inst.pair_device(&path).await }),
                                DeviceAction::Forget => rt.block_on(async { bt_inst.forget_device(&path).await }),
                            };
                            let _ = tx.send_blocking(AppEvent::BtActionComplete);
                            if let Err(e) = res {
                                let _ = tx.send_blocking(AppEvent::Error(format!("Bluetooth action failed: {}", e)));
                            }
                            std::thread::sleep(std::time::Duration::from_millis(500));
                            if let Ok(devices) = rt.block_on(async { bt_inst.get_devices().await }) {
                                let _ = tx.send_blocking(AppEvent::BtScanResult(devices));
                            }
                        }
                    });
                }
                DetailAction::BtTrust(path, on) => {
                    std::thread::spawn(move || {
                        let guard = bt.lock().unwrap();
                        if let Some(ref bt_inst) = *guard {
                            if let Err(e) = rt.block_on(async { bt_inst.set_trusted(&path, on).await }) {
                                let _ = tx.send_blocking(AppEvent::Error(format!("Failed to update trust: {}", e)));
                            }
                            if let Ok(devices) = rt.block_on(async { bt_inst.get_devices().await }) {
                                let _ = tx.send_blocking(AppEvent::BtScanResult(devices));
                            }
                        }
                    });
                }
                DetailAction::EthConnect(profile) => {
                    let _ = tx.send_blocking(AppEvent::WiredConnectStarted(profile.device_path.clone()));
                    std::thread::spawn(move || {
                        let guard = nm.lock().unwrap();
                        if let Some(ref nm_inst) = *guard {
                            let res = rt.block_on(async {
                                nm_inst.activate_wired(&profile.connection_path, &profile.device_path).await
                            });
                            let _ = tx.send_blocking(AppEvent::WiredConnectComplete);
                            if let Err(e) = res {
                                let _ = tx.send_blocking(AppEvent::Error(format!("Connect failed: {}", e)));
                            }
                            if let Ok(profiles) = rt.block_on(async { nm_inst.wired_profiles().await }) {
                                let _ = tx.send_blocking(AppEvent::WiredResult(profiles));
                            }
                        }
                    });
                }
                DetailAction::EthDisconnect(device_path) => {
                    let _ = tx.send_blocking(AppEvent::WiredConnectStarted(device_path.clone()));
                    std::thread::spawn(move || {
                        let guard = nm.lock().unwrap();
                        if let Some(ref nm_inst) = *guard {
                            let res = rt.block_on(async { nm_inst.deactivate_wired(&device_path).await });
                            let _ = tx.send_blocking(AppEvent::WiredConnectComplete);
                            if let Err(e) = res {
                                let _ = tx.send_blocking(AppEvent::Error(format!("Disconnect failed: {}", e)));
                            }
                            if let Ok(profiles) = rt.block_on(async { nm_inst.wired_profiles().await }) {
                                let _ = tx.send_blocking(AppEvent::WiredResult(profiles));
                            }
                        }
                    });
                }
                DetailAction::EthAutoconnect(path, on) => {
                    std::thread::spawn(move || {
                        let guard = nm.lock().unwrap();
                        if let Some(ref nm_inst) = *guard {
                            if let Err(e) = rt.block_on(async { nm_inst.set_autoconnect(&path, on).await }) {
                                let _ = tx.send_blocking(AppEvent::Error(format!("Failed to update autoconnect: {}", e)));
                            }
                            if let Ok(profiles) = rt.block_on(async { nm_inst.wired_profiles().await }) {
                                let _ = tx.send_blocking(AppEvent::WiredResult(profiles));
                            }
                        }
                    });
                }
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

    // The wired row's autoconnect switch moved to the detail page
    // (DetailAction::EthAutoconnect) along with the interface
    // metadata, so there is nothing left to wire here.
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
        // Also covers the detail page: while it's the visible child,
        // `current_tab` still names the tab behind it, so this never
        // matches and polling stays paused -- which is what we want,
        // since a refetch would rebuild the list underneath it.
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
