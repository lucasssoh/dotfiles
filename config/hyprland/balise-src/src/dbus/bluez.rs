//! BlueZ D-Bus client (Phase 3). Adapted from
//! orbit-vendor/src/dbus/bluez.rs: same raw `zbus::Connection` +
//! `call_method` approach as network_manager.rs, one `GetManagedObjects`
//! call to enumerate adapters/devices (BlueZ's own ObjectManager
//! interface) instead of NetworkManager's per-object property reads.

use std::collections::HashMap;
use zbus::zvariant::{ObjectPath, OwnedObjectPath, OwnedValue, Value};
use zbus::Connection;

const BLUEZ: &str = "org.bluez";
const ADAPTER_IFACE: &str = "org.bluez.Adapter1";
const DEVICE_IFACE: &str = "org.bluez.Device1";
const BATTERY_IFACE: &str = "org.bluez.Battery1";
const AGENT_MANAGER_IFACE: &str = "org.bluez.AgentManager1";
const PROPS_IFACE: &str = "org.freedesktop.DBus.Properties";

/// `a{oa{sa{sv}}}` -- BlueZ's ObjectManager shape: object path -> (interface
/// name -> (property name -> value)).
type ManagedObjects = HashMap<OwnedObjectPath, HashMap<String, HashMap<String, OwnedValue>>>;

#[derive(Debug, Clone, Copy, PartialEq)]
pub enum DeviceType {
    Audio,
    Keyboard,
    Mouse,
    Phone,
    Other,
}

#[derive(Debug, Clone)]
pub struct BluetoothDevice {
    pub path: String,
    pub name: String,
    pub address: String,
    pub is_connected: bool,
    pub is_paired: bool,
    pub is_trusted: bool,
    pub rssi: i16,
    pub battery_percentage: Option<u8>,
    pub is_charging: bool,
    pub device_type: DeviceType,
}

#[derive(Clone)]
pub struct BluetoothManager {
    conn: Connection,
    adapter_path: Option<String>,
}

impl BluetoothManager {
    pub async fn new() -> zbus::Result<Self> {
        let conn = Connection::system().await?;
        let adapter_path = find_adapter(&conn).await?;
        Ok(Self { conn, adapter_path })
    }

    fn adapter(&self) -> zbus::Result<&str> {
        self.adapter_path
            .as_deref()
            .ok_or_else(|| zbus::Error::Address("No Bluetooth adapter found".to_string()))
    }

    // ---- power (rfkill-backed -- see the module-level note below) --------

    /// BlueZ's own `Adapter1.Powered` property doesn't reliably reflect an
    /// rfkill soft-block, so power is driven by the `rfkill` CLI instead,
    /// matching Orbit's bluez.rs:126-246 exactly (including this exact
    /// tradeoff -- losing the D-Bus purity buys correct hard/soft-block
    /// detection).
    pub async fn is_powered(&self) -> zbus::Result<bool> {
        match check_rfkill_status() {
            Ok(on) => Ok(on),
            Err(_) => {
                let adapter = self.adapter()?;
                let v = self.get_prop(adapter, ADAPTER_IFACE, "Powered").await?;
                bool::try_from(Value::from(v)).map_err(zbus::Error::from)
            }
        }
    }

    pub async fn set_powered(&self, enabled: bool) -> zbus::Result<()> {
        let arg = if enabled { "unblock" } else { "block" };
        let _ = std::process::Command::new("rfkill").args([arg, "bluetooth"]).status();
        tokio::time::sleep(tokio::time::Duration::from_millis(200)).await;
        Ok(())
    }

    /// Guard called at the top of nearly every action -- up to 6 attempts
    /// x 500ms, matching Orbit's ensure_powered (bluez.rs:178-195).
    async fn ensure_powered(&self) -> zbus::Result<()> {
        for _ in 0..6 {
            if self.is_powered().await.unwrap_or(false) {
                return Ok(());
            }
            tokio::time::sleep(tokio::time::Duration::from_millis(500)).await;
        }
        Err(zbus::Error::Address("Bluetooth adapter is not powered on".to_string()))
    }

    async fn get_prop(&self, path: &str, iface: &str, name: &str) -> zbus::Result<OwnedValue> {
        self.conn
            .call_method(Some(BLUEZ), path, Some(PROPS_IFACE), "Get", &(iface, name))
            .await?
            .body()
            .deserialize::<OwnedValue>()
    }

    // ---- discovery --------------------------------------------------------

    pub async fn start_discovery(&self) -> zbus::Result<()> {
        self.ensure_powered().await?;
        let adapter = self.adapter()?;
        self.conn.call_method(Some(BLUEZ), adapter, Some(ADAPTER_IFACE), "StartDiscovery", &()).await?;
        Ok(())
    }

    pub async fn stop_discovery(&self) -> zbus::Result<()> {
        let adapter = self.adapter()?;
        self.conn.call_method(Some(BLUEZ), adapter, Some(ADAPTER_IFACE), "StopDiscovery", &()).await?;
        Ok(())
    }

    // ---- devices --------------------------------------------------------

    /// One `GetManagedObjects` call gives every device's full property set
    /// directly -- no per-device round trips needed, unlike
    /// NetworkManager's per-object `Properties.Get`. Adapted from
    /// bluez.rs:283-399.
    pub async fn get_devices(&self) -> zbus::Result<Vec<BluetoothDevice>> {
        let objects = get_managed_objects(&self.conn).await?;
        let mut devices = Vec::new();

        for (path, interfaces) in &objects {
            let Some(props) = interfaces.get(DEVICE_IFACE) else { continue };

            let name = props
                .get("Name")
                .or_else(|| props.get("Alias"))
                .and_then(|v| <&str>::try_from(&**v).ok())
                .unwrap_or("Unknown Device")
                .to_string();
            let address = props.get("Address").and_then(|v| <&str>::try_from(&**v).ok()).unwrap_or_default().to_string();
            let is_connected = owned_bool(props.get("Connected"));
            let is_paired = owned_bool(props.get("Paired"));
            let is_trusted = owned_bool(props.get("Trusted"));
            let rssi = props.get("RSSI").and_then(|v| i16::try_from(&**v).ok()).unwrap_or(0);

            // Battery: prefer Device1.BatteryPercentage; else look for a
            // sibling org.bluez.Battery1 interface on the SAME object.
            let (battery_percentage, is_charging) = if let Some(pct) = props.get("BatteryPercentage").and_then(|v| u8::try_from(&**v).ok()) {
                (Some(pct), false)
            } else if let Some(batt_props) = interfaces.get(BATTERY_IFACE) {
                let pct = batt_props.get("Percentage").and_then(|v| u8::try_from(&**v).ok());
                let charging = batt_props
                    .get("State")
                    .and_then(|v| <&str>::try_from(&**v).ok())
                    .map(|s| s == "charging")
                    .unwrap_or(false);
                (pct, charging)
            } else {
                (None, false)
            };

            let device_type = match props.get("Icon").and_then(|v| <&str>::try_from(&**v).ok()) {
                Some("audio-card") | Some("audio-speakers") | Some("audio-headset") | Some("audio-headphones") => DeviceType::Audio,
                Some("input-keyboard") => DeviceType::Keyboard,
                Some("input-mouse") | Some("input-tablet") => DeviceType::Mouse,
                Some("phone") => DeviceType::Phone,
                _ => DeviceType::Other,
            };

            devices.push(BluetoothDevice {
                path: path.to_string(),
                name,
                address,
                is_connected,
                is_paired,
                is_trusted,
                rssi,
                battery_percentage,
                is_charging,
                device_type,
            });
        }

        // Connected first, then paired, then alphabetical -- matches
        // bluez.rs:397.
        devices.sort_by(|a, b| b.is_connected.cmp(&a.is_connected).then(b.is_paired.cmp(&a.is_paired)).then(a.name.cmp(&b.name)));
        Ok(devices)
    }

    pub async fn connect_device(&self, path: &str) -> zbus::Result<()> {
        self.ensure_powered().await?;
        self.conn.call_method(Some(BLUEZ), path, Some(DEVICE_IFACE), "Connect", &()).await?;
        Ok(())
    }

    pub async fn disconnect_device(&self, path: &str) -> zbus::Result<()> {
        self.conn.call_method(Some(BLUEZ), path, Some(DEVICE_IFACE), "Disconnect", &()).await?;
        Ok(())
    }

    /// Blocks until the pairing agent flow completes (BlueZ's own timeout
    /// is ~60s) -- see agent.rs for the PIN/passkey/confirmation prompts
    /// this triggers.
    pub async fn pair_device(&self, path: &str) -> zbus::Result<()> {
        self.ensure_powered().await?;
        self.conn.call_method(Some(BLUEZ), path, Some(DEVICE_IFACE), "Pair", &()).await?;
        Ok(())
    }

    /// Removal is on the adapter, not the device -- adapted from
    /// bluez.rs:446-465.
    pub async fn forget_device(&self, path: &str) -> zbus::Result<()> {
        let adapter = self.adapter()?;
        let path_obj: ObjectPath = path.try_into().map_err(|e: zbus::zvariant::Error| zbus::Error::Variant(e))?;
        self.conn.call_method(Some(BLUEZ), adapter, Some(ADAPTER_IFACE), "RemoveDevice", &(&path_obj)).await?;
        Ok(())
    }

    pub async fn set_trusted(&self, path: &str, trusted: bool) -> zbus::Result<()> {
        self.conn
            .call_method(Some(BLUEZ), path, Some(PROPS_IFACE), "Set", &(DEVICE_IFACE, "Trusted", Value::Bool(trusted)))
            .await?;
        Ok(())
    }

    // ---- pairing agent ----------------------------------------------------

    /// Registers Balise's `BluetoothAgent` (see agent.rs) with capability
    /// `"KeyboardDisplay"`, which is what makes all five PIN/passkey/
    /// confirmation callbacks reachable -- adapted from bluez.rs:60-103.
    /// Must run on a thread with its own tokio runtime so the zbus object
    /// server keeps servicing incoming calls afterward (see app/mod.rs's
    /// registration thread).
    pub async fn register_agent(&mut self, event_tx: async_channel::Sender<super::agent::AgentEvent>) -> zbus::Result<()> {
        let agent = super::agent::BluetoothAgent::new(event_tx);
        let agent_path = "/com/balise/agent";
        let path_obj: ObjectPath = agent_path.try_into().map_err(|e: zbus::zvariant::Error| zbus::Error::Variant(e))?;

        self.conn.object_server().at(agent_path, agent).await?;

        self.conn
            .call_method(Some(BLUEZ), "/org/bluez", Some(AGENT_MANAGER_IFACE), "RegisterAgent", &(&path_obj, "KeyboardDisplay"))
            .await?;
        self.conn.call_method(Some(BLUEZ), "/org/bluez", Some(AGENT_MANAGER_IFACE), "RequestDefaultAgent", &(&path_obj)).await?;

        Ok(())
    }
}

async fn find_adapter(conn: &Connection) -> zbus::Result<Option<String>> {
    let objects = get_managed_objects(conn).await?;
    for (path, interfaces) in objects {
        if interfaces.contains_key(ADAPTER_IFACE) {
            return Ok(Some(path.to_string()));
        }
    }
    Ok(None)
}

async fn get_managed_objects(conn: &Connection) -> zbus::Result<ManagedObjects> {
    conn.call_method(Some(BLUEZ), "/", Some("org.freedesktop.DBus.ObjectManager"), "GetManagedObjects", &())
        .await?
        .body()
        .deserialize()
}

fn owned_bool(v: Option<&OwnedValue>) -> bool {
    v.and_then(|v| bool::try_from(&**v).ok()).unwrap_or(false)
}

/// `rfkill list bluetooth` parsing -- adapted from bluez.rs:126-152.
fn check_rfkill_status() -> Result<bool, String> {
    let output = std::process::Command::new("rfkill")
        .args(["list", "bluetooth"])
        .output()
        .map_err(|e| e.to_string())?;
    let text = String::from_utf8_lossy(&output.stdout).to_lowercase();

    if text.contains("hard blocked: yes") {
        return Err("Bluetooth is hard-blocked (check any physical switch)".to_string());
    }
    Ok(!text.contains("soft blocked: yes"))
}
