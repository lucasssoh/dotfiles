use gtk4::{Application, glib};
use gtk4::prelude::*;
use gtk4::gio::ApplicationFlags;
use std::cell::RefCell;
use std::rc::Rc;
use std::sync::{Arc, Mutex};

pub mod daemon;

use crate::config::Config;
use crate::theme::Theme;
use crate::dbus::{NetworkManager, BluetoothManager};
use crate::dbus::network_manager::{AccessPoint, SecurityType, SavedNetwork, NetworkDetails, VpnProfile, WiredProfile};
use crate::dbus::bluez::{BluetoothDevice, BluetoothDeviceDetails};
use crate::ui::{OrbitWindow, DeviceAction};
use daemon::{DaemonServer, DaemonCommand};

pub enum AppEvent {
    WifiScanResult(Vec<AccessPoint>),
    SavedNetworksResult(Vec<SavedNetwork>),
    NetworkDetailsResult(NetworkDetails),
    BtScanResult(Vec<BluetoothDevice>),
    BtDeviceDetailsResult(BluetoothDeviceDetails),
    WifiPowerState(bool),
    BtPowerState(bool),
    ConnectStarted(String),
    ConnectSuccess,
    ConnectHidden(String, String),
    DisconnectStarted(String),
    BtActionStarted(String, DeviceAction),
    BtTrustStarted(String, bool),
    BtActionComplete,
    BtTrustComplete,
    BtPinRequest(String, async_channel::Sender<String>),
    BtPinDisplay(String, String),
    BtPasskeyRequest(String, async_channel::Sender<u32>),
    BtPasskeyDisplay(String, u32, u16),
    BtConfirmRequest(String, u32, async_channel::Sender<bool>),
    BtAuthRequest(String, async_channel::Sender<bool>),
    BtAgentCancel,
    VpnProfilesResult(Vec<VpnProfile>),
    WiredProfilesResult(Vec<WiredProfile>),
    PublicIpResult(String, String, Vec<String>, bool),
    Error(String),
    Notify(String),
    CaptivePortal(String),
    DaemonCommand(DaemonCommand),
    DaemonStarted(DaemonServer),
}

pub struct OrbitApp {
    app: Application,
    config: Config,
    theme: Rc<RefCell<Theme>>,
    is_daemon: bool,
}

impl OrbitApp {
    pub fn new(config: Config) -> Result<Self, glib::Error> {
        Self::new_with_mode(config, false)
    }
    
    pub fn new_daemon(config: Config) -> Result<Self, glib::Error> {
        Self::new_with_mode(config, true)
    }
    
    fn new_with_mode(config: Config, is_daemon: bool) -> Result<Self, glib::Error> {
        let app = Application::new(Some("com.orbit.app"), ApplicationFlags::empty());
        
        let theme = Theme::load();
        let theme = Rc::new(RefCell::new(theme));
        
        Ok(Self {
            app,
            config,
            theme,
            is_daemon,
        })
    }
    
    pub fn run(&self) -> glib::ExitCode {
        let config = self.config.clone();
        let win_theme = self.theme.clone();
        let is_daemon = self.is_daemon;
        
        self.app.connect_activate(move |app| {
            let app_quit = app.clone();
            glib::unix_signal_add_local(15, move || {
                app_quit.quit();
                glib::ControlFlow::Break
            });
            let app_quit_int = app.clone();
            glib::unix_signal_add_local(2, move || {
                app_quit_int.quit();
                glib::ControlFlow::Break
            });

            let config = config.clone();
            let win_theme = win_theme.clone();
            
            let rt = Arc::new(tokio::runtime::Runtime::new().expect("Failed to create Tokio runtime"));
            let win = OrbitWindow::new(app, config, win_theme.clone());
            
            let nm: Arc<Mutex<Option<NetworkManager>>> = Arc::new(Mutex::new(None));
            let bt: Arc<Mutex<Option<BluetoothManager>>> = Arc::new(Mutex::new(None));
            
            let (tx, rx) = async_channel::unbounded::<AppEvent>();
            
            let current_tab = Rc::new(RefCell::new("wifi".to_string()));

            // Initialization thread
            {
                let rt_init = rt.clone();
                let nm_arc = nm.clone();
                let bt_arc = bt.clone();
                let tx_init = tx.clone();
                
                std::thread::spawn(move || {
                    if is_daemon {
                        match rt_init.block_on(async { DaemonServer::new().await }) {
                            Ok(server) => {
                                let _ = tx_init.send_blocking(AppEvent::DaemonStarted(server));
                            }
                            Err(e) => {
                                log::error!("Failed to start daemon server: {}", e);
                                eprintln!("Error: {}", e);
                                std::process::exit(1);
                            }
                        }
                    }

                    let mut nm_inst = None;
                    for i in 0..5 {
                        if let Ok(inst) = rt_init.block_on(async { NetworkManager::new().await }) {
                            nm_inst = Some(inst);
                            break;
                        }
                        if i < 4 {
                            std::thread::sleep(std::time::Duration::from_secs(1));
                        }
                    }

                    let mut bt_inst = None;
                    for i in 0..5 {
                        if let Ok(inst) = rt_init.block_on(async { BluetoothManager::new().await }) {
                            bt_inst = Some(inst);
                            break;
                        }
                        if i < 4 {
                            std::thread::sleep(std::time::Duration::from_secs(1));
                        }
                    }
                    
                    if let Some(ref nm) = nm_inst {
                        if let Ok(enabled) = rt_init.block_on(async { nm.is_wifi_enabled().await }) {
                            let _ = tx_init.send_blocking(AppEvent::WifiPowerState(enabled));
                            
                            if enabled {
                                log::info!("Not connected yet, waiting for NetworkManager...");
                                let mut attempts = 0;
                                let mut connected_ssid = None;
                                
                                while attempts < 15 {
                                    if let Some(ssid) = rt_init.block_on(async { nm.get_active_ssid().await }) {
                                        log::info!("Connected to {} after {}s", ssid, attempts);
                                        let _ = tx_init.send_blocking(AppEvent::Notify(format!("Connected to {}", ssid)));
                                        connected_ssid = Some(ssid);
                                        break;
                                    }
                                    
                                    let state = rt_init.block_on(async { nm.get_wifi_device_state().await }).unwrap_or(0);
                                    if state < 30 || state > 100 {
                                        if attempts >= 5 {
                                            log::info!("NetworkManager is idle (state {}), stopping wait", state);
                                            break;
                                        }
                                    } else {
                                        log::info!("NetworkManager is busy (state {}), waiting...", state);
                                    }

                                    std::thread::sleep(std::time::Duration::from_secs(1));
                                    attempts += 1;
                                }

                                if connected_ssid.is_none() {
                                    log::info!("Autoconnect timed out, triggering scan");
                                    let _ = rt_init.block_on(async { nm.scan().await });
                                }
                                
                                if let Some(ssid) = connected_ssid {
                                    std::thread::sleep(std::time::Duration::from_secs(2));
                                    if let Ok(connectivity) = rt_init.block_on(async { nm.check_connectivity().await }) {
                                        if connectivity == 2 {
                                            let _ = tx_init.send_blocking(AppEvent::CaptivePortal(ssid));
                                        }
                                    }
                                }
                            }
                            
                            if let Ok(saved) = rt_init.block_on(async { nm.get_saved_networks().await }) {
                                let _ = tx_init.send_blocking(AppEvent::SavedNetworksResult(saved));
                            }
                        }
                    }
                    
                    if let Some(bt) = bt_inst {
                        if let Ok(powered) = rt_init.block_on(async { bt.is_powered().await }) {
                            let _ = tx_init.send_blocking(AppEvent::BtPowerState(powered));
                        }
                        if let Ok(devices) = rt_init.block_on(async { bt.get_devices().await }) {
                            let _ = tx_init.send_blocking(AppEvent::BtScanResult(devices));
                        }
                        
                        // Register Bluetooth Agent
                        let mut bt_mut = bt.clone();
                        let tx_agent = tx_init.clone();
                        let rt_agent = rt_init.clone();
                        std::thread::spawn(move || {
                            if let Err(e) = rt_agent.block_on(async { bt_mut.register_agent(tx_agent).await }) {
                                log::error!("Failed to register Bluetooth Agent: {}", e);
                            }
                        });
                        
                        let mut bt_guard = bt_arc.lock().unwrap();
                        *bt_guard = Some(bt);
                    }
                    
                    let mut nm_guard = nm_arc.lock().unwrap();
                    *nm_guard = nm_inst;
                });
            }
            
            let is_visible = Rc::new(RefCell::new(!is_daemon));
            let last_refresh = Rc::new(RefCell::new(std::time::Instant::now()));
            
            let is_visible_sync = is_visible.clone();
            win.window().connect_notify_local(Some("visible"), move |window, _| {
                *is_visible_sync.borrow_mut() = window.is_visible();
            });

            let is_switching_pwr = Arc::new(Mutex::new(false));
            
            if !is_daemon {
                win.show();
            }
            
            setup_events_receiver(win.clone(), rx.clone(), is_visible.clone(), last_refresh.clone(), nm.clone(), bt.clone(), rt.clone(), tx.clone(), win_theme.clone(), is_switching_pwr.clone(), current_tab.clone());
            setup_ui_callbacks(win.clone(), nm.clone(), bt.clone(), rt.clone(), tx.clone(), current_tab.clone(), is_switching_pwr.clone());
            setup_periodic_refresh(win.clone(), nm, bt, rt.clone(), tx.clone(), is_visible.clone(), current_tab.clone());
        });
        
        self.app.run_with_args(&[] as &[&str])
    }
}

fn setup_events_receiver(
    win: OrbitWindow,
    rx: async_channel::Receiver<AppEvent>,
    is_visible: Rc<RefCell<bool>>,
    last_refresh: Rc<RefCell<std::time::Instant>>,
    nm: Arc<Mutex<Option<NetworkManager>>>,
    bt: Arc<Mutex<Option<BluetoothManager>>>,
    rt: Arc<tokio::runtime::Runtime>,
    tx: async_channel::Sender<AppEvent>,
    win_theme: Rc<RefCell<Theme>>,
    is_switching_pwr: Arc<Mutex<bool>>,
    current_tab: Rc<RefCell<String>>,
) {
    glib::spawn_future_local(async move {
        while let Ok(event) = rx.recv().await {
            match event {
                AppEvent::WifiScanResult(aps) => {
                    win.network_list().set_networks(aps);
                }
                AppEvent::SavedNetworksResult(networks) => {
                    win.saved_networks_list().set_networks(networks);
                }
                AppEvent::NetworkDetailsResult(details) => {
                    win.show_network_details(&details);
                }
                AppEvent::BtDeviceDetailsResult(details) => {
                    win.show_device_details(&details);
                }
                AppEvent::BtScanResult(devices) => {
                    win.device_list().set_devices(devices);
                }
                AppEvent::WifiPowerState(enabled) => {
                    if *is_switching_pwr.lock().unwrap() {
                        continue;
                    }
                    if let Some(tab) = win.stack().visible_child_name() {
                        let tab_str = tab.as_str();
                        if tab_str == "wifi" || tab_str == "saved" {
                            log::info!("UI: Syncing WiFi switch to {}", enabled);
                            win.header().set_power_state(enabled);
                        }
                    }
                }
                AppEvent::BtPowerState(enabled) => {
                    if *is_switching_pwr.lock().unwrap() {
                        continue;
                    }
                    if let Some(tab) = win.stack().visible_child_name() {
                        let tab_str = tab.as_str();
                        if tab_str == "bluetooth" {
                            log::info!("UI: Syncing Bluetooth switch to {}", enabled);
                            win.header().set_power_state(enabled);

                            if enabled {
                                let tx_refresh = tx.clone();
                                let bt_refresh = bt.clone();
                                let rt_refresh = rt.clone();
                                std::thread::spawn(move || {
                                    std::thread::sleep(std::time::Duration::from_millis(1500));
                                    let bt_guard = bt_refresh.lock().unwrap();
                                    if let Some(ref bt_inst) = *bt_guard {
                                        if let Ok(devices) = rt_refresh.block_on(async { bt_inst.get_devices().await }) {
                                            let _ = tx_refresh.send_blocking(AppEvent::BtScanResult(devices));
                                        }
                                    }
                                });
                            }
                        }
                    }
                }
                AppEvent::Error(msg) => {
                    win.network_list().set_connecting_ssid(None);
                    win.network_list().set_disconnecting_ssid(None);
                    win.show_error(&msg);
                }
                AppEvent::Notify(msg) => {
                    std::thread::spawn(move || {
                        let _ = std::process::Command::new("notify-send")
                            .arg("Orbit")
                            .arg(&msg)
                            .arg("--app-name=Orbit")
                            .arg("-i")
                            .arg("network-wireless")
                            .spawn();
                    });
                }
                AppEvent::CaptivePortal(ssid) => {
                    std::thread::spawn(move || {
                        let _ = std::process::Command::new("notify-send")
                            .arg("Orbit")
                            .arg(&format!("Captive portal detected on {} — opening login page...", ssid))
                            .arg("--app-name=Orbit")
                            .arg("-i")
                            .arg("network-wireless")
                            .spawn();
                        let _ = std::process::Command::new("xdg-open")
                            .arg("http://neverssl.com")
                            .spawn();
                    });
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
                        let nm_guard = nm_ref.lock().unwrap();
                        if let Some(ref nm_inst) = *nm_guard {
                            let rt_inner = rt_ref.clone();
                            match rt_inner.block_on(async { nm_inst.get_wireless_devices().await }) {
                                Ok(devices) => {
                                    if let Some(device_path) = devices.get(0) {
                                        let pwd = if password.is_empty() { None } else { Some(password.as_str()) };
                                        let rt_conn = rt_ref.clone();
                                        match rt_conn.block_on(async { nm_inst.connect_hidden(&ssid, pwd, device_path).await }) {
                                            Ok(()) => {
                                                let _ = tx_ref.send_blocking(AppEvent::ConnectSuccess);
                                                let _ = tx_ref.send_blocking(AppEvent::Notify(format!("Connecting to hidden network {}...", ssid)));
                                            }
                                            Err(e) => {
                                                let _ = tx_ref.send_blocking(AppEvent::Error(format!("Hidden connect failed: {}", e)));
                                            }
                                        }
                                    } else {
                                        let _ = tx_ref.send_blocking(AppEvent::Error("No WiFi device found".to_string()));
                                    }
                                }
                                Err(e) => {
                                    let _ = tx_ref.send_blocking(AppEvent::Error(format!("Failed to query WiFi devices: {}", e)));
                                }
                            }
                        }
                    });
                }
                AppEvent::BtActionStarted(path, action) => {
                    win.device_list().set_action_state(Some(path), Some(action));
                }
                AppEvent::BtActionComplete => {
                    win.device_list().set_action_state(None, None);
                }
                AppEvent::BtTrustStarted(_path, _trust) => {
                }
                AppEvent::BtTrustComplete => {
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
                AppEvent::VpnProfilesResult(profiles) => {
                    win.vpn_list().set_profiles(profiles);
                }
                AppEvent::WiredProfilesResult(profiles) => {
                    win.show_wired_overlay(&profiles);
                }
                AppEvent::PublicIpResult(ip, isp, dns_servers, is_secure) => {
                    log::info!("App: Updating UI with IP: {}, ISP: {}, DNS: {:?}", ip, isp, dns_servers);
                    win.vpn_list().set_privacy_info(&ip, &isp, &dns_servers, is_secure);
                }
                AppEvent::DaemonCommand(cmd) => {
                    match cmd {
                        DaemonCommand::Show => {
                            win.show();
                            *is_visible.borrow_mut() = true;
                            
                            // Trigger full refresh on show (with 2 second cooldown)
                            let last_refresh_clone = last_refresh.clone();
                            let should_refresh = {
                                let last = *last_refresh_clone.borrow();
                                last.elapsed() > std::time::Duration::from_secs(2)
                            };
                            
                            if should_refresh {
                                *last_refresh_clone.borrow_mut() = std::time::Instant::now();
                            
                            let nm_ref = nm.clone();
                            let bt_ref = bt.clone();
                            let rt_ref = rt.clone();
                            let tx_ref = tx.clone();
                            
                            std::thread::spawn(move || {
                                log::info!("App: Show background refresh started");
                                let mut current_dns = Vec::new();
                                let nm_guard = nm_ref.lock().unwrap();
                                if let Some(ref nm_inst) = *nm_guard {
                                    if let Ok(enabled) = rt_ref.block_on(async { nm_inst.is_wifi_enabled().await }) {
                                        let _ = tx_ref.send_blocking(AppEvent::WifiPowerState(enabled));
                                    }
                                    if let Ok(aps) = rt_ref.block_on(async { nm_inst.get_access_points().await }) {
                                        let _ = tx_ref.send_blocking(AppEvent::WifiScanResult(aps));
                                    }
                                    if let Ok(profiles) = rt_ref.block_on(async { nm_inst.get_vpn_profiles().await }) {
                                        let _ = tx_ref.send_blocking(AppEvent::VpnProfilesResult(profiles));
                                    }

                                    // Get current DNS
                                    if let Some(ssid) = rt_ref.block_on(async { nm_inst.get_active_ssid().await }) {
                                        if let Ok(details) = rt_ref.block_on(async { nm_inst.get_network_details(&ssid).await }) {
                        current_dns.extend(details.ipv4_dns);
                        current_dns.extend(details.ipv6_dns);
                                        }
                                    }
                                }
                                let bt_guard = bt_ref.lock().unwrap();
                                if let Some(ref bt_inst) = *bt_guard {
                                    if let Ok(powered) = rt_ref.block_on(async { bt_inst.is_powered().await }) {
                                        let _ = tx_ref.send_blocking(AppEvent::BtPowerState(powered));
                                    }
                                    if let Ok(devices) = rt_ref.block_on(async { bt_inst.get_devices().await }) {
                                        let _ = tx_ref.send_blocking(AppEvent::BtScanResult(devices));
                                    }
                                }

                                // Trigger IP check
                                log::info!("App: Fetching public IP info (Show)...");
                                let client_res = reqwest::blocking::Client::builder()
                                    .timeout(std::time::Duration::from_secs(5))
                                    .user_agent("curl/8.5.0")
                                    .build();
                                
                                if let Ok(client) = client_res {
                                    let providers = [
                                        "https://ifconfig.me/all.json",
                                        "https://api.ipify.org?format=json",
                                        "https://ipapi.co/json/"
                                    ];

                                    for url in providers {
                                        if let Ok(response) = client.get(url).send() {
                                            if let Ok(text) = response.text() {
                                                if let Ok(json) = serde_json::from_str::<serde_json::Value>(&text) {
                                                    let ip = json["ip"].as_str() 
                                                        .or_else(|| json["query"].as_str())
                                                        .or_else(|| json["ip_addr"].as_str())
                                                        .unwrap_or("Unknown").to_string();
                                                    let isp = json["org"].as_str()
                                                        .or_else(|| json["asn_org"].as_str())
                                                        .or_else(|| json["isp"].as_str())
                                                        .unwrap_or("Direct Connection").to_string();
                                                    let is_secure = isp.to_lowercase().contains("vpn") || 
                                                                   isp.to_lowercase().contains("hosting");
                                                    let _ = tx_ref.send_blocking(AppEvent::PublicIpResult(ip, isp, current_dns.clone(), is_secure));
                                                    return;
                                                }
                                            }
                                        }
                                    }
                                }
                            });
                            }
                        }
                        DaemonCommand::Hide => {
                            win.hide();
                            *is_visible.borrow_mut() = false;
                        }
                        DaemonCommand::Toggle(position, tab) => {
                            log::info!("App: Daemon command Toggle received (tab: {:?})", tab);
                            let switch_tab_only = *is_visible.borrow()
                                && tab.as_deref().map_or(false, |t| t != current_tab.borrow().as_str());

                            if switch_tab_only {
                                if let Some(pos) = position {
                                    win.set_position(&pos);
                                }
                                if let Some(t) = tab {
                                    win.set_tab(&t);
                                    *current_tab.borrow_mut() = t;
                                }
                            } else if *is_visible.borrow() {
                                win.hide();
                                *is_visible.borrow_mut() = false;
                            } else {
                                if let Some(pos) = position {
                                    win.set_position(&pos);
                                }
                                
                                let _current_target_tab = tab.clone();
                                if let Some(t) = tab {
                                    win.set_tab(&t);
                                    *current_tab.borrow_mut() = t;
                                }
                                win.show();
                                *is_visible.borrow_mut() = true;

                                
                                // Trigger full refresh on show (with 2 second cooldown)
                                let last_refresh_clone = last_refresh.clone();
                                let should_refresh = {
                                    let last = *last_refresh_clone.borrow();
                                    last.elapsed() > std::time::Duration::from_secs(2)
                                };
                                
                                if should_refresh {
                                    *last_refresh_clone.borrow_mut() = std::time::Instant::now();
                                
                                let nm_ref = nm.clone();
                                let bt_ref = bt.clone();
                                let rt_ref = rt.clone();
                                let tx_ref = tx.clone();
                                
                                std::thread::spawn(move || {
                                    log::info!("App: Toggle background refresh started");
                                    let mut current_dns = Vec::new();
                                    let nm_guard = nm_ref.lock().unwrap();
                                    if let Some(ref nm_inst) = *nm_guard {
                                        if let Ok(enabled) = rt_ref.block_on(async { nm_inst.is_wifi_enabled().await }) {
                                            let _ = tx_ref.send_blocking(AppEvent::WifiPowerState(enabled));
                                        }
                                        if let Ok(aps) = rt_ref.block_on(async { nm_inst.get_access_points().await }) {
                                            let _ = tx_ref.send_blocking(AppEvent::WifiScanResult(aps));
                                        }
                                        if let Ok(profiles) = rt_ref.block_on(async { nm_inst.get_vpn_profiles().await }) {
                                            let _ = tx_ref.send_blocking(AppEvent::VpnProfilesResult(profiles));
                                        }

                                        // Get current DNS
                                        if let Some(ssid) = rt_ref.block_on(async { nm_inst.get_active_ssid().await }) {
                                            if let Ok(details) = rt_ref.block_on(async { nm_inst.get_network_details(&ssid).await }) {
                                                current_dns.extend(details.ipv4_dns);
                                                current_dns.extend(details.ipv6_dns);
                                            }
                                        }
                                    }
                                    let bt_guard = bt_ref.lock().unwrap();
                                    if let Some(ref bt_inst) = *bt_guard {
                                        if let Ok(powered) = rt_ref.block_on(async { bt_inst.is_powered().await }) {
                                            let _ = tx_ref.send_blocking(AppEvent::BtPowerState(powered));
                                        }
                                        if let Ok(devices) = rt_ref.block_on(async { bt_inst.get_devices().await }) {
                                            let _ = tx_ref.send_blocking(AppEvent::BtScanResult(devices));
                                        }
                                    }

                                    // Trigger IP check in background with multi-provider fallback
                                    let tx_ip = tx_ref.clone();
                                    std::thread::spawn(move || {
                                        log::info!("App: Background IP check triggered (Toggle)");
                                        let client_res = reqwest::blocking::Client::builder()
                                            .timeout(std::time::Duration::from_secs(5))
                                            .user_agent("curl/8.5.0")
                                            .build();
                                        
                                        if let Ok(client) = client_res {
                                            let providers = [
                                                "https://ifconfig.me/all.json",
                                                "https://api.ipify.org?format=json",
                                                "https://ipapi.co/json/"
                                            ];

                                            for url in providers {
                                                log::info!("App: Trying IP provider (Toggle): {}", url);
                                                if let Ok(response) = client.get(url).send() {
                                                    if let Ok(text) = response.text() {
                                                        log::info!("App: IP response (Toggle): {}", text);
                                                        if let Ok(json) = serde_json::from_str::<serde_json::Value>(&text) {
                                                            let ip = json["ip"].as_str() 
                                                                .or_else(|| json["query"].as_str())
                                                                .or_else(|| json["ip_addr"].as_str())
                                                                .unwrap_or("Unknown").to_string();
                                                                
                                                            let isp = json["org"].as_str()
                                                                .or_else(|| json["asn_org"].as_str())
                                                                .or_else(|| json["isp"].as_str())
                                                                .unwrap_or("Direct Connection").to_string();
                                                                
                                                            let is_secure = isp.to_lowercase().contains("vpn") || 
                                                                           isp.to_lowercase().contains("hosting");

                                                            log::info!("App: Found IP: {} via {}", ip, url);
                                                            let _ = tx_ip.send_blocking(AppEvent::PublicIpResult(ip, isp, current_dns.clone(), is_secure));
                                                            return;
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    });
                                });
                                }
                            }
                        }
                        DaemonCommand::ReloadTheme => {
                            let new_theme = Theme::load();
                            *win_theme.borrow_mut() = new_theme;
                            win.apply_theme();
                        }
                        DaemonCommand::ReloadConfig => {
                            win.reload_config();
                        }
                        DaemonCommand::Quit => {
                            std::process::exit(0);
                        }
                    }
                }
                AppEvent::DaemonStarted(server) => {
                    let tx_cmd = tx.clone();
                    server.run(move |cmd| {
                        let _ = tx_cmd.send_blocking(AppEvent::DaemonCommand(cmd));
                    });
                }
            }
        }
    });
}

fn setup_ui_callbacks(
    win: OrbitWindow,
    nm: Arc<Mutex<Option<NetworkManager>>>,
    bt: Arc<Mutex<Option<BluetoothManager>>>,
    rt: Arc<tokio::runtime::Runtime>,
    tx: async_channel::Sender<AppEvent>,
    current_tab: Rc<RefCell<String>>,
    is_switching_pwr: Arc<Mutex<bool>>,
) {
    let header = win.header().clone();
    let stack = win.stack().clone();

    // Tab buttons
    let stack_wifi = stack.clone();
    let header_wifi = header.clone();
    let current_tab_wifi = current_tab.clone();
    let nm_wifi = nm.clone();
    let rt_wifi = rt.clone();
    let tx_wifi = tx.clone();
    let is_switching_wifi = is_switching_pwr.clone();
    header.wifi_tab().connect_clicked(move |_| {
        *current_tab_wifi.borrow_mut() = "wifi".to_string();
        stack_wifi.set_visible_child_name("wifi");
        header_wifi.set_tab("wifi");
        let nm = nm_wifi.clone();
        let rt = rt_wifi.clone();
        let tx = tx_wifi.clone();
        let is_switching = is_switching_wifi.clone();
        std::thread::spawn(move || {
            let nm_guard = nm.lock().unwrap();
            if let Some(ref nm_inst) = *nm_guard {
                if let Ok(enabled) = rt.block_on(async { nm_inst.is_wifi_enabled().await }) {
                    if !*is_switching.lock().unwrap() {
                        let _ = tx.send_blocking(AppEvent::WifiPowerState(enabled));
                    }
                }
            }
        });
    });

    let stack_bt = stack.clone();
    let header_bt = header.clone();
    let current_tab_bt = current_tab.clone();
    let bt_tab = bt.clone();
    let rt_bt_tab = rt.clone();
    let tx_bt_tab = tx.clone();
    let is_switching_bt_tab = is_switching_pwr.clone();
    header.bluetooth_tab().connect_clicked(move |_| {
        *current_tab_bt.borrow_mut() = "bluetooth".to_string();
        stack_bt.set_visible_child_name("bluetooth");
        header_bt.set_tab("bluetooth");
        let bt = bt_tab.clone();
        let rt = rt_bt_tab.clone();
        let tx = tx_bt_tab.clone();
        let is_switching = is_switching_bt_tab.clone();
        std::thread::spawn(move || {
            let bt_guard = bt.lock().unwrap();
            if let Some(ref bt_inst) = *bt_guard {
                if let Ok(enabled) = rt.block_on(async { bt_inst.is_powered().await }) {
                    if !*is_switching.lock().unwrap() {
                        let _ = tx.send_blocking(AppEvent::BtPowerState(enabled));
                    }
                }
            }
        });
    });

    let stack_vpn = stack.clone();
    let header_vpn = header.clone();
    let current_tab_vpn = current_tab.clone();
    let nm_vpn_tab = nm.clone();
    let rt_vpn_tab = rt.clone();
    let tx_vpn_tab = tx.clone();
    header.vpn_tab().connect_clicked(move |_| {
        log::info!("UI: VPN tab button clicked");
        *current_tab_vpn.borrow_mut() = "vpn".to_string();
        stack_vpn.set_visible_child_name("vpn");
        header_vpn.set_tab("vpn");
        
        let nm = nm_vpn_tab.clone();
        let rt = rt_vpn_tab.clone();
        let tx = tx_vpn_tab.clone();
        std::thread::spawn(move || {
            log::info!("App: VPN tab activation thread started");
            let mut current_dns = Vec::new();
            let nm_guard = nm.lock().unwrap();
            if let Some(ref nm_inst) = *nm_guard {
                match rt.block_on(async { nm_inst.get_vpn_profiles().await }) {
                    Ok(profiles) => {
                        log::info!("App: Found {} VPN profiles", profiles.len());
                        let _ = tx.send_blocking(AppEvent::VpnProfilesResult(profiles));
                    }
                    Err(e) => {
                        log::error!("App: Failed to fetch VPN profiles: {}", e);
                    }
                }

                // Get current DNS servers from active connection
                if let Some(ssid) = rt.block_on(async { nm_inst.get_active_ssid().await }) {
                    if let Ok(details) = rt.block_on(async { nm_inst.get_network_details(&ssid).await }) {
                        current_dns.extend(details.ipv4_dns);
                        current_dns.extend(details.ipv6_dns);
                    }
                }
            }
            
            // Fetch public IP info using a more reliable endpoint that avoids Cloudflare challenges
            log::info!("App: Fetching public IP info (Manual Click)...");
            let client_res = reqwest::blocking::Client::builder()
                .timeout(std::time::Duration::from_secs(5))
                .user_agent("curl/8.5.0")
                .build();
            
            if let Ok(client) = client_res {
                // Try multiple providers for redundancy
                let providers = [
                    "https://ifconfig.me/all.json",
                    "https://api.ipify.org?format=json",
                    "https://ipapi.co/json/"
                ];

                for url in providers {
                    log::info!("App: Trying IP provider (Manual Click): {}", url);
                    match client.get(url).send() {
                        Ok(response) => {
                            if let Ok(text) = response.text() {
                                log::info!("App: Received response from {}", url);
                                if let Ok(json) = serde_json::from_str::<serde_json::Value>(&text) {
                                    let ip = json["ip"].as_str() 
                                        .or_else(|| json["query"].as_str())
                                        .or_else(|| json["ip_addr"].as_str())
                                        .unwrap_or("Unknown").to_string();
                                        
                                    let isp = json["org"].as_str()
                                        .or_else(|| json["asn_org"].as_str())
                                        .or_else(|| json["isp"].as_str())
                                        .unwrap_or("Direct Connection").to_string();
                                        
                                    let is_secure = isp.to_lowercase().contains("vpn") || 
                                                   isp.to_lowercase().contains("hosting") ||
                                                   url.contains("vpn");

                                    log::info!("App: Detected IP: {}, ISP: {}", ip, isp);
                                    let _ = tx.send_blocking(AppEvent::PublicIpResult(ip, isp, current_dns.clone(), is_secure));
                                    return;
                                }
                            }
                        }
                        Err(e) => log::warn!("App: Provider {} failed (Manual Click): {}", url, e),
                    }
                }
            }

            let _ = tx.send_blocking(AppEvent::PublicIpResult(
                "Unavailable".to_string(), 
                "Check connection".to_string(), 
                current_dns,
                false
            ));
        });
    });

    let _win_wired_btn = win.clone();
    let nm_wired_btn = nm.clone();
    let rt_wired_btn = rt.clone();
    let tx_wired_btn = tx.clone();
    header.wired_button().connect_clicked(move |_| {
        log::info!("UI: Wired button clicked");
        let nm = nm_wired_btn.clone();
        let rt = rt_wired_btn.clone();
        let tx = tx_wired_btn.clone();
        std::thread::spawn(move || {
            let nm_guard = nm.lock().unwrap();
            if let Some(ref nm_inst) = *nm_guard {
                match rt.block_on(async { nm_inst.get_wired_profiles().await }) {
                    Ok(profiles) => {
                        log::info!("App: Found {} wired profiles", profiles.len());
                        let _ = tx.send_blocking(AppEvent::WiredProfilesResult(profiles));
                    }
                    Err(e) => {
                        log::error!("App: Failed to fetch wired profiles: {}", e);
                        let _ = tx.send_blocking(AppEvent::Error(format!("Failed to fetch wired profiles: {}", e)));
                    }
                }
            }
        });
    });

    let win_saved = win.clone();
    let nm_saved = nm.clone();
    let rt_saved = rt.clone();
    let tx_saved = tx.clone();
    win.network_list().set_on_show_saved(move || {
        win_saved.show_saved_networks();
        let nm = nm_saved.clone();
        let rt = rt_saved.clone();
        let tx = tx_saved.clone();
        std::thread::spawn(move || {
            let nm_guard = nm.lock().unwrap();
            if let Some(ref nm_inst) = *nm_guard {
                match rt.block_on(async { nm_inst.get_saved_networks().await }) {
                    Ok(saved) => {
                        let _ = tx.send_blocking(AppEvent::SavedNetworksResult(saved));
                    }
                    Err(e) => {
                        let _ = tx.send_blocking(AppEvent::Error(format!("Failed to fetch saved networks: {}", e)));
                    }
                }
            }
        });
    });

    // WiFi Scan
    let nm_scan = nm.clone();
    let rt_scan = rt.clone();
    let tx_scan = tx.clone();
    win.network_list().scan_button().connect_clicked(move |_| {
        let nm = nm_scan.clone();
        let rt = rt_scan.clone();
        let tx = tx_scan.clone();
        std::thread::spawn(move || {
            let nm_guard = nm.lock().unwrap();
            if let Some(ref nm_inst) = *nm_guard {
                let _ = rt.block_on(async { nm_inst.scan().await });
                std::thread::sleep(std::time::Duration::from_millis(1500));
                if let Ok(aps) = rt.block_on(async { nm_inst.get_access_points().await }) {
                    let _ = tx.send_blocking(AppEvent::WifiScanResult(aps));
                }
            }
        });
    });

    let nm_auto = nm.clone();
    let rt_auto = rt.clone();
    let tx_auto = tx.clone();
    win.saved_networks_list().set_on_autoconnect_toggle(move |path: String, enabled: bool| {
        let nm = nm_auto.clone();
        let rt = rt_auto.clone();
        let tx = tx_auto.clone();
        std::thread::spawn(move || {
            let nm_guard = nm.lock().unwrap();
            if let Some(ref nm_inst) = *nm_guard {
                match rt.block_on(async { nm_inst.set_autoconnect(&path, enabled).await }) {
                    Ok(()) => {
                        std::thread::sleep(std::time::Duration::from_millis(100));
                        match rt.block_on(async { nm_inst.get_saved_networks().await }) {
                            Ok(saved) => {
                                let _ = tx.send_blocking(AppEvent::SavedNetworksResult(saved));
                            }
                            Err(e) => {
                                let _ = tx.send_blocking(AppEvent::Error(format!("Failed to refresh: {}", e)));
                            }
                        }
                    }
                    Err(e) => {
                        let _ = tx.send_blocking(AppEvent::Error(format!("Failed to update autoconnect: {}", e)));
                        if let Ok(saved) = rt.block_on(async { nm_inst.get_saved_networks().await }) {
                            let _ = tx.send_blocking(AppEvent::SavedNetworksResult(saved));
                        }
                    }
                }
            }
        });
    });

    let nm_forget = nm.clone();
    let rt_forget = rt.clone();
    let tx_forget = tx.clone();
    win.saved_networks_list().set_on_forget(move |path: String| {
        let nm = nm_forget.clone();
        let rt = rt_forget.clone();
        let tx = tx_forget.clone();
        std::thread::spawn(move || {
            let nm_guard = nm.lock().unwrap();
            if let Some(ref nm_inst) = *nm_guard {
                match rt.block_on(async { nm_inst.forget_network(&path).await }) {
                    Ok(()) => {
                        let _ = tx.send_blocking(AppEvent::Notify("Network forgotten".to_string()));
                        if let Ok(saved) = rt.block_on(async { nm_inst.get_saved_networks().await }) {
                            let _ = tx.send_blocking(AppEvent::SavedNetworksResult(saved));
                        }
                    }
                    Err(e) => {
                        let _ = tx.send_blocking(AppEvent::Error(format!("Forget failed: {}", e)));
                    }
                }
            }
        });
    });
    
    let nm_conn = nm.clone();
    let rt_conn = rt.clone();
    let tx_conn = tx.clone();
    let win_conn_hidden = win.clone();
    let tx_conn_hidden = tx.clone();
    win.network_list().set_on_connect_hidden(move || {
        let tx = tx_conn_hidden.clone();
        win_conn_hidden.show_hidden_dialog(move |data| {
            if let Some((ssid, password)) = data {
                let _ = tx.send_blocking(AppEvent::ConnectHidden(ssid, password));
            }
        });
    });

    let win_connect = win.clone();
    win.network_list().set_on_connect(move |ap: AccessPoint| {
        let nm = nm_conn.clone();
        let rt = rt_conn.clone();
        let tx = tx_conn.clone();
        let ap_path = ap.device_path.clone();
        let ssid = ap.ssid.clone();
        
        if ap.is_connected {
            let ap_path_inner = ap.path.clone();
            let ssid_inner = ap.ssid.clone();
            let _ = tx.send_blocking(AppEvent::DisconnectStarted(ssid_inner.clone()));
            let nm_val = nm.clone();
            let rt_val = rt.clone();
            let tx_val = tx.clone();
            std::thread::spawn(move || {
                let nm_guard = nm_val.lock().unwrap();
                if let Some(ref nm_inst) = *nm_guard {
                    let _ = rt_val.block_on(async { nm_inst.disconnect_ap(&ssid_inner, &ap_path_inner).await });
                    std::thread::sleep(std::time::Duration::from_millis(1000));
                    let _ = tx_val.send_blocking(AppEvent::ConnectSuccess);
                    std::thread::sleep(std::time::Duration::from_millis(500));
                    if let Ok(aps) = rt_val.block_on(async { nm_inst.get_access_points().await }) {
                        let _ = tx_val.send_blocking(AppEvent::WifiScanResult(aps));
                    }
                }
            });
        } else {
            let win_p = win_connect.clone();
            let nm_check = nm.clone();
            let rt_check = rt.clone();
            let ssid_check = ssid.clone();
            
            let has_saved = {
                let nm_guard = nm_check.lock().unwrap();
                if let Some(ref nm_inst) = *nm_guard {
                    rt_check.block_on(async { nm_inst.has_saved_connection(&ssid_check).await })
                } else {
                    false
                }
            };

            if ap.security == SecurityType::None || has_saved {
                let _ = tx.send_blocking(AppEvent::ConnectStarted(ssid.clone()));
                let nm_val = nm.clone();
                let rt_val = rt.clone();
                let tx_val = tx.clone();
                let ssid_val = ssid.clone();
                let ap_path_val = ap_path.clone();
                std::thread::spawn(move || {
                    let nm_guard = nm_val.lock().unwrap();
                    if let Some(ref nm_inst) = *nm_guard {
                        match rt_val.block_on(async { nm_inst.connect_to_network(&ssid_val, None, &ap_path_val).await }) {
                            Ok(()) => {
                                std::thread::sleep(std::time::Duration::from_millis(1000));
                                let _ = tx_val.send_blocking(AppEvent::ConnectSuccess);
                                let _ = tx_val.send_blocking(AppEvent::Notify(format!("Connected to {}", ssid_val)));
                                if let Ok(aps) = rt_val.block_on(async { nm_inst.get_access_points().await }) {
                                    let _ = tx_val.send_blocking(AppEvent::WifiScanResult(aps));
                                }
                            }
                            Err(e) => { 
                                log::error!("UI: Connect failed for '{}': {}", ssid_val, e);
                                let _ = tx_val.send_blocking(AppEvent::Error(format!("Connect failed: {}", e))); 
                            }
                        }
                    }
                });
            } else {
                let ssid_val = ssid.clone();
                let nm_val = nm.clone();
                let rt_val = rt.clone();
                let tx_val = tx.clone();
                let ap_path_val = ap_path.clone();
                win_p.show_password_dialog(&ssid, move |password| {
                    if let Some(pwd) = password {
                        let nm_inner = nm_val.clone();
                        let rt_inner = rt_val.clone();
                        let tx_inner = tx_val.clone();
                        let ssid_inner = ssid_val.clone();
                        let ap_path_inner = ap_path_val.clone();

                        let _ = tx_inner.send_blocking(AppEvent::ConnectStarted(ssid_inner.clone()));
                        std::thread::spawn(move || {
                            let nm_guard = nm_inner.lock().unwrap();
                            if let Some(ref nm_inst) = *nm_guard {
                                match rt_inner.block_on(async { nm_inst.connect_to_network(&ssid_inner, Some(&pwd), &ap_path_inner).await }) {
                                    Ok(()) => {
                                        std::thread::sleep(std::time::Duration::from_millis(1000));
                                        let _ = tx_inner.send_blocking(AppEvent::ConnectSuccess);
                                        let _ = tx_inner.send_blocking(AppEvent::Notify(format!("Connected to {}", ssid_inner)));
                                        if let Ok(aps) = rt_inner.block_on(async { nm_inst.get_access_points().await }) {
                                            let _ = tx_inner.send_blocking(AppEvent::WifiScanResult(aps));
                                        }
                                    }
                                    Err(e) => { 
                                        log::error!("UI: Connect failed for '{}': {}", ssid_inner, e);
                                        let _ = tx_inner.send_blocking(AppEvent::Error(format!("Connect failed: {}", e))); 
                                    }
                                }
                            }
                        });
                    }
                });
            }
        }
    });
    
    let nm_details = nm.clone();
    let rt_details = rt.clone();
    let tx_details = tx.clone();
    win.network_list().set_on_details(move |ssid: String| {
        let nm = nm_details.clone();
        let rt = rt_details.clone();
        let tx = tx_details.clone();
        std::thread::spawn(move || {
            let nm_guard = nm.lock().unwrap();
            if let Some(ref nm_inst) = *nm_guard {
                match rt.block_on(async { nm_inst.get_network_details(&ssid).await }) {
                    Ok(details) => {
                        let _ = tx.send_blocking(AppEvent::NetworkDetailsResult(details));
                    }
                    Err(e) => {
                        let _ = tx.send_blocking(AppEvent::Error(format!("Failed to get network details: {}", e)));
                    }
                }
            }
        });
    });

    let bt_details = bt.clone();
    let rt_details_bt = rt.clone();
    let tx_details_bt = tx.clone();
    win.device_list().set_on_details(move |path: String| {
        let bt = bt_details.clone();
        let rt = rt_details_bt.clone();
        let tx = tx_details_bt.clone();
        std::thread::spawn(move || {
            let bt_guard = bt.lock().unwrap();
            if let Some(ref bt_inst) = *bt_guard {
                match rt.block_on(async { bt_inst.get_device_details(&path).await }) {
                    Ok(details) => {
                        let _ = tx.send_blocking(AppEvent::BtDeviceDetailsResult(details));
                    }
                    Err(e) => {
                        let _ = tx.send_blocking(AppEvent::Error(format!("Failed to get device details: {}", e)));
                    }
                }
            }
        });
    });

    let bt_trust = bt.clone();
    let rt_trust = rt.clone();
    let tx_trust = tx.clone();
    win.set_on_details_action(move |path, trusted| {
        let bt = bt_trust.clone();
        let rt = rt_trust.clone();
        let tx = tx_trust.clone();
        let _ = tx.send_blocking(AppEvent::BtTrustStarted(path.clone(), trusted));
        std::thread::spawn(move || {
            let bt_guard = bt.lock().unwrap();
            if let Some(ref bt_inst) = *bt_guard {
                match rt.block_on(async { bt_inst.set_trusted(&path, trusted).await }) {
                    Ok(()) => {
                        let _ = tx.send_blocking(AppEvent::BtTrustComplete);
                        // Refresh details
                        if let Ok(details) = rt.block_on(async { bt_inst.get_device_details(&path).await }) {
                            let _ = tx.send_blocking(AppEvent::BtDeviceDetailsResult(details));
                        }
                    }
                    Err(e) => {
                        let _ = tx.send_blocking(AppEvent::BtTrustComplete);
                        let _ = tx.send_blocking(AppEvent::Error(format!("Failed to update trust status: {}", e)));
                    }
                }
            }
        });
    });

    let bt_forget = bt.clone();
    let rt_forget_bt = rt.clone();
    let tx_forget_bt = tx.clone();
    win.set_on_forget_device(move |path| {
        let bt = bt_forget.clone();
        let rt = rt_forget_bt.clone();
        let tx = tx_forget_bt.clone();
        let _ = tx.send_blocking(AppEvent::BtActionStarted(path.clone(), DeviceAction::Forget));
        std::thread::spawn(move || {
            let bt_guard = bt.lock().unwrap();
            if let Some(ref bt_inst) = *bt_guard {
                match rt.block_on(async { bt_inst.forget_device(&path).await }) {
                    Ok(()) => {
                        let _ = tx.send_blocking(AppEvent::BtActionComplete);
                        let _ = tx.send_blocking(AppEvent::Notify("Device forgotten".to_string()));
                        std::thread::sleep(std::time::Duration::from_millis(500));
                        if let Ok(devices) = rt.block_on(async { bt_inst.get_devices().await }) {
                            let _ = tx.send_blocking(AppEvent::BtScanResult(devices));
                        }
                    }
                    Err(e) => {
                        let _ = tx.send_blocking(AppEvent::BtActionComplete);
                        let _ = tx.send_blocking(AppEvent::Error(format!("Forget failed: {}", e)));
                    }
                }
            }
        });
    });
    
    let bt_scan = bt.clone();
    let rt_bt = rt.clone();
    let tx_bt = tx.clone();
    let dev_list = win.device_list().clone();
    win.device_list().scan_button().connect_clicked(move |_| {
        dev_list.show_scanning();
        let bt = bt_scan.clone();
        let rt = rt_bt.clone();
        let tx = tx_bt.clone();
        std::thread::spawn(move || {
            let bt_guard = bt.lock().unwrap();
            if let Some(ref bt_inst) = *bt_guard {
                let _ = rt.block_on(async { bt_inst.start_discovery().await });
                std::thread::sleep(std::time::Duration::from_secs(5));
                let _ = rt.block_on(async { bt_inst.stop_discovery().await });
                if let Ok(devices) = rt.block_on(async { bt_inst.get_devices().await }) {
                    let _ = tx.send_blocking(AppEvent::BtScanResult(devices));
                }
            }
        });
    });
    
    let bt_act = bt.clone();
    let rt_act = rt.clone();
    let tx_act = tx.clone();
    win.device_list().set_on_action(move |path: String, action: DeviceAction| {
        let bt = bt_act.clone();
        let rt = rt_act.clone();
        let tx = tx_act.clone();
        let _ = tx.send_blocking(AppEvent::BtActionStarted(path.clone(), action.clone()));
        std::thread::spawn(move || {
            let bt_guard = bt.lock().unwrap();
            if let Some(ref bt_inst) = *bt_guard {
                let res = match action {
                    DeviceAction::Connect => rt.block_on(async { bt_inst.connect_device(&path).await }),
                    DeviceAction::Disconnect => rt.block_on(async { bt_inst.disconnect_device(&path).await }),
                    DeviceAction::Pair => rt.block_on(async { bt_inst.pair_device(&path).await }),
                    DeviceAction::Forget => rt.block_on(async { bt_inst.forget_device(&path).await }),
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
    });

    let nm_vpn_act = nm.clone();
    let rt_vpn_act = rt.clone();
    let tx_vpn_act = tx.clone();
    win.vpn_list().set_on_toggle(move |path, state| {
        let nm = nm_vpn_act.clone();
        let rt = rt_vpn_act.clone();
        let tx = tx_vpn_act.clone();
        std::thread::spawn(move || {
            let nm_guard = nm.lock().unwrap();
            if let Some(ref nm_inst) = *nm_guard {
                let res = if state {
                    rt.block_on(async { nm_inst.activate_vpn(&path).await })
                } else {
                    rt.block_on(async { nm_inst.deactivate_vpn(&path).await })
                };
                
                if let Err(e) = res {
                    let _ = tx.send_blocking(AppEvent::Error(format!("VPN Action failed: {}", e)));
                }
                
                // Refresh list
                std::thread::sleep(std::time::Duration::from_millis(500));
                if let Ok(profiles) = rt.block_on(async { nm_inst.get_vpn_profiles().await }) {
                    let _ = tx.send_blocking(AppEvent::VpnProfilesResult(profiles));
                }
            }
        });
    });
    
    let _win_wired_conn = win.clone();
    let nm_wired_conn = nm.clone();
    let rt_wired_conn = rt.clone();
    let tx_wired_conn = tx.clone();
    win.set_wired_connect_callback(move |conn_path, dev_path| {
        let nm = nm_wired_conn.clone();
        let rt = rt_wired_conn.clone();
        let tx = tx_wired_conn.clone();
        std::thread::spawn(move || {
            let nm_guard = nm.lock().unwrap();
            if let Some(ref nm_inst) = *nm_guard {
                if let Err(e) = rt.block_on(async { nm_inst.activate_wired_connection(&conn_path, &dev_path).await }) {
                    let _ = tx.send_blocking(AppEvent::Error(format!("Failed to connect wired: {}", e)));
                }
                std::thread::sleep(std::time::Duration::from_millis(500));
                if let Ok(profiles) = rt.block_on(async { nm_inst.get_wired_profiles().await }) {
                    let _ = tx.send_blocking(AppEvent::WiredProfilesResult(profiles));
                }
            }
        });
    });
    
    let _win_wired_disc = win.clone();
    let nm_wired_disc = nm.clone();
    let rt_wired_disc = rt.clone();
    let tx_wired_disc = tx.clone();
    win.set_wired_disconnect_callback(move |dev_path| {
        let nm = nm_wired_disc.clone();
        let rt = rt_wired_disc.clone();
        let tx = tx_wired_disc.clone();
        std::thread::spawn(move || {
            let nm_guard = nm.lock().unwrap();
            if let Some(ref nm_inst) = *nm_guard {
                if let Err(e) = rt.block_on(async { nm_inst.deactivate_wired_connection(&dev_path).await }) {
                    let _ = tx.send_blocking(AppEvent::Error(format!("Failed to disconnect wired: {}", e)));
                }
                std::thread::sleep(std::time::Duration::from_millis(500));
                if let Ok(profiles) = rt.block_on(async { nm_inst.get_wired_profiles().await }) {
                    let _ = tx.send_blocking(AppEvent::WiredProfilesResult(profiles));
                }
            }
        });
    });
    
    let _win_wired_auto = win.clone();
    let nm_wired_auto = nm.clone();
    let rt_wired_auto = rt.clone();
    let tx_wired_auto = tx.clone();
    win.set_wired_autoconnect_callback(move |conn_path, enabled| {
        let nm = nm_wired_auto.clone();
        let rt = rt_wired_auto.clone();
        let tx = tx_wired_auto.clone();
        std::thread::spawn(move || {
            let nm_guard = nm.lock().unwrap();
            if let Some(ref nm_inst) = *nm_guard {
                if let Err(e) = rt.block_on(async { nm_inst.set_autoconnect(&conn_path, enabled).await }) {
                    let _ = tx.send_blocking(AppEvent::Error(format!("Failed to set autoconnect: {}", e)));
                }
                if let Ok(profiles) = rt.block_on(async { nm_inst.get_wired_profiles().await }) {
                    let _ = tx.send_blocking(AppEvent::WiredProfilesResult(profiles));
                }
            }
        });
    });
    
    let nm_pwr = nm.clone();
    let bt_pwr_ref = bt.clone();
    let rt_pwr = rt.clone();
    let tx_pwr = tx.clone();
    let current_tab_pwr = current_tab.clone();
    let win_pwr_switch = win.clone();
    let is_switching_toggle = is_switching_pwr.clone();
    win.header().power_switch().connect_active_notify(move |switch| {
        let header = win_pwr_switch.header();
        if header.is_programmatic_update() {
            return;
        }

        let enabled = switch.is_active();
        let nm = nm_pwr.clone();
        let bt = bt_pwr_ref.clone();
        let rt = rt_pwr.clone();
        let tx = tx_pwr.clone();
        let tab = current_tab_pwr.borrow().clone();
        let is_switching = is_switching_toggle.clone();
        
        *is_switching.lock().unwrap() = true;
        let is_switching_end = is_switching.clone();
        let nm_thread = nm.clone();
        let rt_thread = rt.clone();
        let tx_thread = tx.clone();
        let bt_thread = bt.clone();
        let rt_bt_thread = rt.clone();
        let tx_bt_thread = tx.clone();

        std::thread::spawn(move || {
            if tab == "wifi" || tab == "saved" {
                let nm_guard = nm_thread.lock().unwrap();
                if let Some(ref nm_inst) = *nm_guard {
                    let _ = rt_thread.block_on(async { nm_inst.set_wifi_enabled(enabled).await });
                    let _ = tx_thread.send_blocking(AppEvent::WifiPowerState(enabled));
                }
            } else if tab == "bluetooth" {
                let bt_guard = bt_thread.lock().unwrap();
                if let Some(ref bt_inst) = *bt_guard {
                    match rt_bt_thread.block_on(async { bt_inst.set_powered(enabled).await }) {
                        Ok(()) => {
                            let _ = tx_bt_thread.send_blocking(AppEvent::BtPowerState(enabled));
                        },
                        Err(e) => {
                            let _ = tx_bt_thread.send_blocking(AppEvent::Error(format!("Failed to toggle Bluetooth: {}", e)));
                            if let Ok(actual) = rt_bt_thread.block_on(async { bt_inst.is_powered().await }) {
                                let _ = tx_bt_thread.send_blocking(AppEvent::BtPowerState(actual));
                            }
                        }
                    }
                }
            }
            std::thread::sleep(std::time::Duration::from_secs(2));
            *is_switching_end.lock().unwrap() = false;
        });
    });
}

fn setup_periodic_refresh(
    _win: OrbitWindow,
    nm: Arc<Mutex<Option<NetworkManager>>>,
    bt: Arc<Mutex<Option<BluetoothManager>>>,
    rt: Arc<tokio::runtime::Runtime>,
    tx: async_channel::Sender<AppEvent>,
    is_visible: Rc<RefCell<bool>>,
    current_tab: Rc<RefCell<String>>,
) {
    let stack = _win.stack().clone();
    glib::timeout_add_local(std::time::Duration::from_secs(5), move || {
        if !*is_visible.borrow() {
            return glib::ControlFlow::Continue;
        }
        
        let nm = nm.clone();
        let bt = bt.clone();
        let rt = rt.clone();
        let tx = tx.clone();
        let tab = current_tab.borrow().clone();
        let current_visible = stack.visible_child_name().map(|s| s.to_string());
        
        if Some(tab.clone()) != current_visible {
             return glib::ControlFlow::Continue;
        }
        
        std::thread::spawn(move || {
            if tab == "wifi" {
                let nm_guard = nm.lock().unwrap();
                if let Some(ref nm_inst) = *nm_guard {
                    if let Ok(aps) = rt.block_on(async { nm_inst.get_access_points().await }) {
                        let _ = tx.send_blocking(AppEvent::WifiScanResult(aps));
                    }
                }
            } else if tab == "bluetooth" {
                let bt_guard = bt.lock().unwrap();
                if let Some(ref bt_inst) = *bt_guard {
                    if let Ok(devices) = rt.block_on(async { bt_inst.get_devices().await }) {
                        let _ = tx.send_blocking(AppEvent::BtScanResult(devices));
                    }
                }
            } else if tab == "saved" {
                let nm_guard = nm.lock().unwrap();
                if let Some(ref nm_inst) = *nm_guard {
                    if let Ok(saved) = rt.block_on(async { nm_inst.get_saved_networks().await }) {
                        let _ = tx.send_blocking(AppEvent::SavedNetworksResult(saved));
                    }
                }
            }
        });
        
        glib::ControlFlow::Continue
    });
}
