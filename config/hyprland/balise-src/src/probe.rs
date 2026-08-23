//! Headless terminal diagnostics -- `balise status`/`list`/`saved`. No
//! GTK, no daemon: just NetworkManager over D-Bus, printed as a table.
//! This is the whole Phase 1a deliverable (see the project plan): proving
//! the backend correct from Bash, cross-checked against `nmcli`, before
//! any WiFi UI exists to click through.

use crate::dbus::{BluetoothManager, NetworkManager};

fn runtime() -> tokio::runtime::Runtime {
    tokio::runtime::Runtime::new().expect("failed to create tokio runtime")
}

pub fn status() {
    runtime().block_on(async {
        let nm = match NetworkManager::new().await {
            Ok(nm) => nm,
            Err(e) => {
                eprintln!("balise: failed to connect to NetworkManager: {}", e);
                std::process::exit(1);
            }
        };

        match nm.is_wifi_enabled().await {
            Ok(enabled) => println!("WiFi radio: {}", if enabled { "enabled" } else { "disabled" }),
            Err(e) => eprintln!("WiFi radio: error ({})", e),
        }

        match nm.wireless_devices().await {
            Ok(devices) => {
                println!("WiFi devices: {}", devices.len());
                for d in &devices {
                    println!("  {}", d);
                }
            }
            Err(e) => eprintln!("WiFi devices: error ({})", e),
        }

        match nm.wifi_device_state().await {
            Ok(state) => println!("Device state: {}", state),
            Err(e) => eprintln!("Device state: error ({})", e),
        }

        match nm.active_wifi_ssid().await {
            Some(ssid) => println!("Active: {}", ssid),
            None => println!("Active: (none)"),
        }
    });
}

pub fn list(do_scan: bool) {
    runtime().block_on(async {
        let nm = match NetworkManager::new().await {
            Ok(nm) => nm,
            Err(e) => {
                eprintln!("balise: failed to connect to NetworkManager: {}", e);
                std::process::exit(1);
            }
        };

        if do_scan {
            if let Err(e) = nm.request_scan().await {
                eprintln!("balise: scan request failed: {}", e);
            }
            tokio::time::sleep(tokio::time::Duration::from_millis(1500)).await;
        }

        match nm.access_points().await {
            Ok(aps) => {
                if aps.is_empty() {
                    println!("(no access points found)");
                }
                for ap in aps {
                    let connected = if ap.is_connected { " [connected]" } else { "" };
                    let saved = if ap.is_saved { " [saved]" } else { "" };
                    println!(
                        "  {:<32} {:>3}%  {:<5}{}{}",
                        ap.ssid,
                        ap.signal,
                        ap.security.label(),
                        connected,
                        saved
                    );
                }
            }
            Err(e) => {
                eprintln!("balise: failed to list access points: {}", e);
                std::process::exit(1);
            }
        }
    });
}

pub fn set_autoconnect(path: &str, on: bool) {
    runtime().block_on(async {
        let nm = match NetworkManager::new().await {
            Ok(nm) => nm,
            Err(e) => {
                eprintln!("balise: failed to connect to NetworkManager: {}", e);
                std::process::exit(1);
            }
        };
        match nm.set_autoconnect(path, on).await {
            Ok(()) => println!("autoconnect set to {}", on),
            Err(e) => {
                eprintln!("balise: failed to set autoconnect: {}", e);
                std::process::exit(1);
            }
        }
    });
}

pub fn ethernet() {
    runtime().block_on(async {
        let nm = match NetworkManager::new().await {
            Ok(nm) => nm,
            Err(e) => {
                eprintln!("balise: failed to connect to NetworkManager: {}", e);
                std::process::exit(1);
            }
        };

        match nm.wired_profiles().await {
            Ok(profiles) => {
                if profiles.is_empty() {
                    println!("(no wired devices found)");
                }
                for p in profiles {
                    let active = if p.is_active { " [active]" } else { "" };
                    let carrier = if p.has_carrier { "carrier" } else { "no carrier" };
                    let auto = if p.autoconnect { "auto" } else { "manual" };
                    println!("  {:<20} {:<16} {:<10} {:<7}{}", p.device_name, p.name, carrier, auto, active);
                    if p.is_active {
                        println!("      ip: {}  gw: {}  dns: {:?}  mac: {}", p.ip4_address, p.gateway, p.dns_servers, p.mac_address);
                    }
                }
            }
            Err(e) => {
                eprintln!("balise: failed to list wired profiles: {}", e);
                std::process::exit(1);
            }
        }
    });
}

pub fn bluetooth_status() {
    runtime().block_on(async {
        let bt = match BluetoothManager::new().await {
            Ok(bt) => bt,
            Err(e) => {
                eprintln!("balise: failed to connect to BlueZ: {}", e);
                std::process::exit(1);
            }
        };

        match bt.is_powered().await {
            Ok(on) => println!("Bluetooth radio: {}", if on { "enabled" } else { "disabled" }),
            Err(e) => eprintln!("Bluetooth radio: error ({})", e),
        }

        match bt.get_devices().await {
            Ok(devices) => {
                if devices.is_empty() {
                    println!("(no known devices -- try `balise bluetooth-scan`)");
                }
                for d in devices {
                    let state = if d.is_connected {
                        "connected"
                    } else if d.is_paired {
                        "paired"
                    } else {
                        "available"
                    };
                    let battery = d.battery_percentage.map(|p| format!(" {}%", p)).unwrap_or_default();
                    println!("  {:<28} {:<10}{}  ({})", d.name, state, battery, d.address);
                }
            }
            Err(e) => eprintln!("Bluetooth devices: error ({})", e),
        }
    });
}

pub fn bluetooth_scan() {
    runtime().block_on(async {
        let bt = match BluetoothManager::new().await {
            Ok(bt) => bt,
            Err(e) => {
                eprintln!("balise: failed to connect to BlueZ: {}", e);
                std::process::exit(1);
            }
        };

        if let Err(e) = bt.start_discovery().await {
            eprintln!("balise: failed to start discovery: {}", e);
            std::process::exit(1);
        }
        println!("Scanning for 5s...");
        tokio::time::sleep(tokio::time::Duration::from_secs(5)).await;
        let _ = bt.stop_discovery().await;

        match bt.get_devices().await {
            Ok(devices) => {
                for d in devices {
                    println!("  {:<28} {} ({})", d.name, if d.is_paired { "paired" } else { "unpaired" }, d.address);
                }
            }
            Err(e) => eprintln!("balise: failed to list devices: {}", e),
        }
    });
}

pub fn saved() {
    runtime().block_on(async {
        let nm = match NetworkManager::new().await {
            Ok(nm) => nm,
            Err(e) => {
                eprintln!("balise: failed to connect to NetworkManager: {}", e);
                std::process::exit(1);
            }
        };

        match nm.saved_networks().await {
            Ok(nets) => {
                if nets.is_empty() {
                    println!("(no saved networks)");
                }
                for n in nets {
                    let active = if n.is_active { " [active]" } else { "" };
                    let auto = if n.autoconnect { "auto" } else { "manual" };
                    let label = if n.id != n.ssid {
                        format!("{} (id: {})", n.ssid, n.id)
                    } else {
                        n.ssid.clone()
                    };
                    println!("  {:<40} {:<7}{}", label, auto, active);
                }
            }
            Err(e) => {
                eprintln!("balise: failed to list saved networks: {}", e);
                std::process::exit(1);
            }
        }
    });
}
