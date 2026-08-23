//! Headless terminal diagnostics -- `balise status`/`list`/`saved`. No
//! GTK, no daemon: just NetworkManager over D-Bus, printed as a table.
//! This is the whole Phase 1a deliverable (see the project plan): proving
//! the backend correct from Bash, cross-checked against `nmcli`, before
//! any WiFi UI exists to click through.

use crate::dbus::NetworkManager;

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
