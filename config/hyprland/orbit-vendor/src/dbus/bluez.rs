use zbus::Connection;
use zbus::zvariant::ObjectPath;
use async_channel::Sender;
use crate::app::AppEvent;

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct BluetoothDevice {
    pub path: String,
    pub name: String,
    pub address: String,
    pub device_type: Option<DeviceType>,
    pub is_connected: bool,
    pub is_paired: bool,
    pub is_trusted: bool,
    pub rssi: i16,
    pub battery_percentage: Option<u8>,
    pub is_charging: bool,
}

#[derive(Debug, Clone, Default, serde::Serialize, serde::Deserialize)]
pub struct BluetoothDeviceDetails {
    pub name: String,
    pub address: String,
    pub is_connected: bool,
    pub is_paired: bool,
    pub is_trusted: bool,
    pub battery_percentage: Option<u8>,
    pub is_charging: bool,
    pub rssi: i16,
    pub device_type: Option<DeviceType>,
    pub path: String,
}

#[derive(Debug, Clone, Copy, PartialEq, serde::Serialize, serde::Deserialize)]
pub enum DeviceType {
    Audio,
    Keyboard,
    Mouse,
    Phone,
}

#[derive(Clone)]
pub struct BluetoothManager {
    conn: Connection,
    adapter_path: Option<String>,
    agent_registered: bool,
}

impl BluetoothManager {
    pub async fn new() -> zbus::Result<Self> {
        let conn = Connection::system().await?;
        let adapter_path = Self::find_adapter(&conn).await?;
        Ok(Self { 
            conn, 
            adapter_path,
            agent_registered: false,
        })
    }

    pub async fn register_agent(&mut self, event_tx: Sender<AppEvent>) -> zbus::Result<()> {
        if self.agent_registered {
            return Ok(());
        }

        let agent = crate::dbus::agent::BluetoothAgent::new(event_tx);
        let agent_path = "/com/orbit/agent";
        
        self.conn
            .object_server()
            .at(agent_path, agent)
            .await?;
        
        let manager_path = ObjectPath::try_from("/org/bluez")
            .map_err(|e| zbus::Error::Variant(e))?;
        
        let path_obj = ObjectPath::try_from(agent_path)
            .map_err(|e| zbus::Error::Variant(e))?;

        // Register as default agent
        self.conn
            .call_method(
                Some("org.bluez"),
                &manager_path,
                Some("org.bluez.AgentManager1"),
                "RegisterAgent",
                &(&path_obj, "KeyboardDisplay"),
            )
            .await?;

        self.conn
            .call_method(
                Some("org.bluez"),
                &manager_path,
                Some("org.bluez.AgentManager1"),
                "RequestDefaultAgent",
                &(&path_obj),
            )
            .await?;

        self.agent_registered = true;
        log::info!("Bluetooth Agent registered successfully at {}", agent_path);
        Ok(())
    }

    async fn find_adapter(conn: &Connection) -> zbus::Result<Option<String>> {
        let reply: std::collections::HashMap<zbus::zvariant::OwnedObjectPath, std::collections::HashMap<String, std::collections::HashMap<String, zbus::zvariant::OwnedValue>>> = conn
            .call_method(
                Some("org.bluez"),
                "/",
                Some("org.freedesktop.DBus.ObjectManager"),
                "GetManagedObjects",
                &(),
            )
            .await?
            .body()
            .deserialize()?;

        for (path, interfaces) in reply {
            if interfaces.contains_key("org.bluez.Adapter1") {
                return Ok(Some(path.to_string()));
            }
        }
        Ok(None)
    }

    fn check_rfkill_status() -> Result<bool, String> {
        let output = std::process::Command::new("rfkill")
            .args(["list", "bluetooth"])
            .output()
            .map_err(|e| format!("Failed to run rfkill: {}", e))?;

        if !output.status.success() {
            return Err("rfkill command failed".to_string());
        }

        let stdout = String::from_utf8_lossy(&output.stdout);
        let lower = stdout.to_lowercase();

        if lower.contains("soft blocked: yes") {
            return Ok(false);
        }

        if lower.contains("hard blocked: yes") {
            return Err("Bluetooth is hard-blocked. Check your hardware switch or BIOS settings.".to_string());
        }

        if lower.contains("soft blocked: no") || lower.is_empty() {
            return Ok(true);
        }

        Ok(true)
    }

    pub async fn is_powered(&self) -> zbus::Result<bool> {
        match Self::check_rfkill_status() {
            Ok(powered) => Ok(powered),
            Err(e) => {
                log::warn!("Failed to check rfkill status: {}", e);
                let adapter_str = self.adapter_path.as_ref()
                    .ok_or_else(|| zbus::Error::Address("No Bluetooth adapter found".to_string()))?;
                let adapter = ObjectPath::try_from(adapter_str.as_str()).map_err(|e| zbus::Error::Variant(e))?;
                let reply = self.conn
                    .call_method(
                        Some("org.bluez"),
                        &adapter,
                        Some("org.freedesktop.DBus.Properties"),
                        "Get",
                        &("org.bluez.Adapter1", "Powered"),
                    )
                    .await?
                    .body()
                    .deserialize::<zbus::zvariant::OwnedValue>()?;
                bool::try_from(reply).map_err(zbus::Error::from)
            }
        }
    }

    async fn ensure_powered(&self) -> zbus::Result<()> {
        let mut attempts = 0;
        while attempts < 6 {
            match self.is_powered().await {
                Ok(true) => return Ok(()),
                Ok(false) => {
                    log::info!("Bluetooth adapter not powered yet, waiting (attempt {})...", attempts + 1);
                    tokio::time::sleep(std::time::Duration::from_millis(500)).await;
                }
                Err(e) => {
                    log::warn!("Failed to check Bluetooth power state: {}", e);
                    tokio::time::sleep(std::time::Duration::from_millis(500)).await;
                }
            }
            attempts += 1;
        }
        Err(zbus::Error::Address("Bluetooth adapter is not powered on".to_string()))
    }

    pub async fn set_powered(&self, powered: bool) -> zbus::Result<()> {
        log::info!("BlueZ: Setting powered to {}", powered);

        if powered {
            log::info!("BlueZ: Running rfkill unblock bluetooth");
            let status = std::process::Command::new("rfkill")
                .arg("unblock")
                .arg("bluetooth")
                .status()
                .map_err(|e| zbus::Error::Address(format!("Failed to run rfkill: {}", e)))?;

            if !status.success() {
                log::warn!("rfkill unblock returned non-zero exit code");
            }

            tokio::time::sleep(std::time::Duration::from_millis(200)).await;

            match Self::check_rfkill_status() {
                Ok(true) => {
                    log::info!("BlueZ: Power state set successfully to {}", powered);
                    Ok(())
                }
                Ok(false) => {
                    Err(zbus::Error::Address("Bluetooth is blocked. Failed to unblock.".to_string()))
                }
                Err(msg) => {
                    if msg.contains("hard-blocked") {
                        Err(zbus::Error::Address(msg))
                    } else {
                        log::info!("BlueZ: Power state set successfully to {}", powered);
                        Ok(())
                    }
                }
            }
        } else {
            log::info!("BlueZ: Running rfkill block bluetooth");
            let status = std::process::Command::new("rfkill")
                .arg("block")
                .arg("bluetooth")
                .status()
                .map_err(|e| zbus::Error::Address(format!("Failed to run rfkill: {}", e)))?;

            if !status.success() {
                log::warn!("rfkill block returned non-zero exit code");
            }

            log::info!("BlueZ: Power state set successfully to {}", powered);
            Ok(())
        }
    }

    pub async fn start_discovery(&self) -> zbus::Result<()> {
        self.ensure_powered().await?;
        let adapter_str = self.adapter_path.as_ref()
            .ok_or_else(|| zbus::Error::Address("No Bluetooth adapter found".to_string()))?;
        let adapter = ObjectPath::try_from(adapter_str.as_str()).map_err(|e| zbus::Error::Variant(e))?;
        
        self.conn
            .call_method(
                Some("org.bluez"),
                &adapter,
                Some("org.bluez.Adapter1"),
                "StartDiscovery",
                &(),
            )
            .await?;
        Ok(())
    }

    pub async fn stop_discovery(&self) -> zbus::Result<()> {
        let adapter_str = self.adapter_path.as_ref()
            .ok_or_else(|| zbus::Error::Address("No Bluetooth adapter found".to_string()))?;
        let adapter = ObjectPath::try_from(adapter_str.as_str()).map_err(|e| zbus::Error::Variant(e))?;
        
        self.conn
            .call_method(
                Some("org.bluez"),
                &adapter,
                Some("org.bluez.Adapter1"),
                "StopDiscovery",
                &(),
            )
            .await?;
        Ok(())
    }

    pub async fn get_devices(&self) -> zbus::Result<Vec<BluetoothDevice>> {
        let reply: std::collections::HashMap<zbus::zvariant::OwnedObjectPath, std::collections::HashMap<String, std::collections::HashMap<String, zbus::zvariant::OwnedValue>>> = self.conn
            .call_method(
                Some("org.bluez"),
                "/",
                Some("org.freedesktop.DBus.ObjectManager"),
                "GetManagedObjects",
                &(),
            )
            .await?
            .body()
            .deserialize()?;

        let mut devices = Vec::new();
        for (path, interfaces) in reply {
            if let Some(props) = interfaces.get("org.bluez.Device1") {
                let name = props.get("Name")
                    .or_else(|| props.get("Alias"))
                    .and_then(|v| {
                        let inner = zbus::zvariant::Value::try_from(v).ok()?;
                        <&str>::try_from(&inner).ok().map(|s| s.to_string())
                    })
                    .unwrap_or_else(|| "Unknown Device".to_string());

                let address = props.get("Address")
                    .and_then(|v| {
                        let inner = zbus::zvariant::Value::try_from(v).ok()?;
                        <&str>::try_from(&inner).ok().map(|s| s.to_string())
                    })
                    .unwrap_or_default();

                let is_connected = props.get("Connected")
                    .and_then(|v| {
                        let inner = zbus::zvariant::Value::try_from(v).ok()?;
                        bool::try_from(&inner).ok()
                    })
                    .unwrap_or(false);

                let is_paired = props.get("Paired")
                    .and_then(|v| {
                        let inner = zbus::zvariant::Value::try_from(v).ok()?;
                        bool::try_from(&inner).ok()
                    })
                    .unwrap_or(false);

                let is_trusted = props.get("Trusted")
                    .and_then(|v| {
                        let inner = zbus::zvariant::Value::try_from(v).ok()?;
                        bool::try_from(&inner).ok()
                    })
                    .unwrap_or(false);

                let rssi = props.get("RSSI")
                    .and_then(|v| {
                        let inner = zbus::zvariant::Value::try_from(v).ok()?;
                        i16::try_from(&inner).ok()
                    })
                    .unwrap_or(0);

                let battery_percentage = props.get("BatteryPercentage")
                    .and_then(|v| {
                        let inner = zbus::zvariant::Value::try_from(v).ok()?;
                        u8::try_from(&inner).ok()
                    });

                // If battery is missing, we could theoretically try to find the Battery1 interface here too,
                // but GetManagedObjects usually returns all interfaces. Let's see if Battery1 is present.
                let mut final_battery = battery_percentage;
                let mut is_charging = false;
                if let Some(bat_props) = interfaces.get("org.bluez.Battery1") {
                    if final_battery.is_none() {
                        final_battery = bat_props.get("Percentage")
                            .and_then(|v| {
                                let inner = zbus::zvariant::Value::try_from(v).ok()?;
                                u8::try_from(&inner).ok()
                            });
                    }
                    is_charging = bat_props.get("State")
                        .and_then(|v| {
                            let inner = zbus::zvariant::Value::try_from(v).ok()?;
                            <&str>::try_from(&inner).ok().map(|s| s == "charging")
                        })
                        .unwrap_or(false);
                }

                let icon = props.get("Icon")
                    .and_then(|v| {
                        let inner = zbus::zvariant::Value::try_from(v).ok()?;
                        <&str>::try_from(&inner).ok().map(|s| s.to_string())
                    });

                let device_type = match icon.as_deref() {
                    Some("audio-card") | Some("audio-speakers") | Some("audio-headset") | Some("audio-headphones") => Some(DeviceType::Audio),
                    Some("input-keyboard") => Some(DeviceType::Keyboard),
                    Some("input-mouse") | Some("input-tablet") => Some(DeviceType::Mouse),
                    Some("phone") => Some(DeviceType::Phone),
                    _ => None,
                };

                devices.push(BluetoothDevice {
                    path: path.to_string(),
                    name,
                    address,
                    device_type,
                    is_connected,
                    is_paired,
                    is_trusted,
                    rssi,
                    battery_percentage: final_battery,
                    is_charging,
                });
            }
        }

        devices.sort_by(|a, b| b.is_connected.cmp(&a.is_connected).then_with(|| b.is_paired.cmp(&a.is_paired)).then_with(|| a.name.cmp(&b.name)));
        Ok(devices)
    }

    pub async fn connect_device(&self, path: &str) -> zbus::Result<()> {
        self.ensure_powered().await?;
        let p = ObjectPath::try_from(path).map_err(|e| zbus::Error::Variant(e))?;
        self.conn
            .call_method(
                Some("org.bluez"),
                &p,
                Some("org.bluez.Device1"),
                "Connect",
                &(),
            )
            .await?;
        Ok(())
    }

    pub async fn disconnect_device(&self, path: &str) -> zbus::Result<()> {
        self.ensure_powered().await?;
        let p = ObjectPath::try_from(path).map_err(|e| zbus::Error::Variant(e))?;
        self.conn
            .call_method(
                Some("org.bluez"),
                &p,
                Some("org.bluez.Device1"),
                "Disconnect",
                &(),
            )
            .await?;
        Ok(())
    }

    pub async fn pair_device(&self, path: &str) -> zbus::Result<()> {
        self.ensure_powered().await?;
        let p = ObjectPath::try_from(path).map_err(|e| zbus::Error::Variant(e))?;
        self.conn
            .call_method(
                Some("org.bluez"),
                &p,
                Some("org.bluez.Device1"),
                "Pair",
                &(),
            )
            .await?;
        Ok(())
    }

    pub async fn forget_device(&self, path: &str) -> zbus::Result<()> {
        self.ensure_powered().await?;
        let adapter_str = self.adapter_path.as_ref()
            .ok_or_else(|| zbus::Error::Address("No Bluetooth adapter found".to_string()))?;
        let adapter = ObjectPath::try_from(adapter_str.as_str()).map_err(|e| zbus::Error::Variant(e))?;
        
        let path_obj = ObjectPath::try_from(path)
            .map_err(|e| zbus::Error::Variant(e))?;

        self.conn
            .call_method(
                Some("org.bluez"),
                &adapter,
                Some("org.bluez.Adapter1"),
                "RemoveDevice",
                &(path_obj),
            )
            .await?;
        Ok(())
    }

    pub async fn set_trusted(&self, path: &str, trusted: bool) -> zbus::Result<()> {
        self.ensure_powered().await?;
        let p = ObjectPath::try_from(path).map_err(|e| zbus::Error::Variant(e))?;
        let value = zbus::zvariant::Value::Bool(trusted);
        self.conn
            .call_method(
                Some("org.bluez"),
                &p,
                Some("org.freedesktop.DBus.Properties"),
                "Set",
                &("org.bluez.Device1", "Trusted", value),
            )
            .await?;
        Ok(())
    }

    pub async fn get_device_details(&self, path: &str) -> zbus::Result<BluetoothDeviceDetails> {
        self.ensure_powered().await?;
        let p = ObjectPath::try_from(path).map_err(|e| zbus::Error::Variant(e))?;
        
        let reply: std::collections::HashMap<String, zbus::zvariant::OwnedValue> = self.conn
            .call_method(
                Some("org.bluez"),
                &p,
                Some("org.freedesktop.DBus.Properties"),
                "GetAll",
                &("org.bluez.Device1"),
            )
            .await?
            .body()
            .deserialize()?;

        let name = reply.get("Name")
            .or_else(|| reply.get("Alias"))
            .and_then(|ov| {
                let v = zbus::zvariant::Value::try_from(ov).ok()?;
                <&str>::try_from(&v).ok().map(|s| s.to_string())
            })
            .unwrap_or_else(|| "Unknown Device".to_string());

        let address = reply.get("Address")
            .and_then(|ov| {
                let v = zbus::zvariant::Value::try_from(ov).ok()?;
                <&str>::try_from(&v).ok().map(|s| s.to_string())
            })
            .unwrap_or_default();

        let is_connected = reply.get("Connected")
            .and_then(|ov| {
                let v = zbus::zvariant::Value::try_from(ov).ok()?;
                bool::try_from(&v).ok()
            })
            .unwrap_or(false);

        let is_paired = reply.get("Paired")
            .and_then(|ov| {
                let v = zbus::zvariant::Value::try_from(ov).ok()?;
                bool::try_from(&v).ok()
            })
            .unwrap_or(false);

        let is_trusted = reply.get("Trusted")
            .and_then(|ov| {
                let v = zbus::zvariant::Value::try_from(ov).ok()?;
                bool::try_from(&v).ok()
            })
            .unwrap_or(false);

        let rssi = reply.get("RSSI")
            .and_then(|ov| {
                let v = zbus::zvariant::Value::try_from(ov).ok()?;
                i16::try_from(&v).ok()
            })
            .unwrap_or(0);

        let battery_percentage = reply.get("BatteryPercentage")
            .and_then(|ov| {
                let v = zbus::zvariant::Value::try_from(ov).ok()?;
                u8::try_from(&v).ok()
            })
            .or_else(|| {
                // Try fetching from org.bluez.Battery1 if Device1 doesn't have it
                None
            });
        
        // If we still don't have battery, try a separate call to Battery1
        let mut final_battery = battery_percentage;
        let mut is_charging = false;
        
        // Try to get properties from Battery1 interface
        if let Ok(battery_props_reply) = self.conn
            .call_method(
                Some("org.bluez"),
                &p,
                Some("org.freedesktop.DBus.Properties"),
                "GetAll",
                &("org.bluez.Battery1"),
            )
            .await {
                if let Ok(props) = battery_props_reply.body().deserialize::<std::collections::HashMap<String, zbus::zvariant::OwnedValue>>() {
                    if final_battery.is_none() {
                        if let Some(val) = props.get("Percentage") {
                            let v = zbus::zvariant::Value::try_from(val).ok();
                            final_battery = v.and_then(|val| u8::try_from(&val).ok());
                        }
                    }
                    if let Some(val) = props.get("State") {
                        if let Ok(v) = zbus::zvariant::Value::try_from(val) {
                            is_charging = <&str>::try_from(&v).ok().map(|s| s == "charging").unwrap_or(false);
                        }
                    }
                }
            }

        let icon = reply.get("Icon")
            .and_then(|ov| {
                let v = zbus::zvariant::Value::try_from(ov).ok()?;
                <&str>::try_from(&v).ok().map(|s| s.to_string())
            });

        let device_type = match icon.as_deref() {
            Some("audio-card") | Some("audio-speakers") | Some("audio-headset") | Some("audio-headphones") => Some(DeviceType::Audio),
            Some("input-keyboard") => Some(DeviceType::Keyboard),
            Some("input-mouse") | Some("input-tablet") => Some(DeviceType::Mouse),
            Some("phone") => Some(DeviceType::Phone),
            _ => None,
        };

        Ok(BluetoothDeviceDetails {
            name,
            address,
            is_connected,
            is_paired,
            is_trusted,
            battery_percentage: final_battery,
            is_charging,
            rssi,
            device_type,
            path: path.to_string(),
        })
    }
}
