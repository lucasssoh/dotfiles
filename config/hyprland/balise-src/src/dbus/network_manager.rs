//! NetworkManager D-Bus client -- WiFi only (no VPN, no wired yet, see the
//! project plan's roadmap). Adapted from
//! orbit-vendor/src/dbus/network_manager.rs: same raw `zbus::Connection` +
//! `call_method` approach (no typed proxies, no D-Bus signal
//! subscriptions -- 100% poll + refetch-after-action, matching Orbit's
//! proven behavior), but with `get_prop`/`set_prop`/typed-`prop_*` helpers
//! replacing Orbit's ~30 hand-written `Properties.Get/Set` blocks.
//!
//! Two bugs fixed while porting (both documented in the project plan's
//! §6.1/§6.2, both fall out of `active_connections()` reading
//! `Connection.Active.Connection` -- a pattern Orbit already uses
//! correctly elsewhere, just not in `get_saved_networks`/`get_active_ssid`):
//! - `saved_networks()`'s `is_active` is computed correctly (Orbit's
//!   equivalent always returns false: it compares a Settings-path against
//!   ActiveConnection-paths, different namespaces).
//! - `active_wifi_ssid()` resolves the real 802-11-wireless.ssid instead
//!   of the connection's renameable `Id` label.
//!
//! Documented gap kept as-is (project plan §6.3): `connect()` only writes
//! `key-mgmt = "wpa-psk"` for a *new* profile, so WPA3-SAE/enterprise
//! networks can't get a new profile created this way (already-saved
//! profiles of any type still activate fine via ActivateConnection).

use std::collections::HashMap;
use zbus::zvariant::{ObjectPath, OwnedObjectPath, OwnedValue, Value};
use zbus::Connection;

use super::types::{AccessPoint, SavedNetwork, SecurityType, WiredProfile};

const NM: &str = "org.freedesktop.NetworkManager";
const NM_PATH: &str = "/org/freedesktop/NetworkManager";
const NM_SETTINGS_PATH: &str = "/org/freedesktop/NetworkManager/Settings";
const PROPS_IFACE: &str = "org.freedesktop.DBus.Properties";
const NM_IFACE: &str = "org.freedesktop.NetworkManager";
const DEVICE_IFACE: &str = "org.freedesktop.NetworkManager.Device";
const WIRELESS_IFACE: &str = "org.freedesktop.NetworkManager.Device.Wireless";
const AP_IFACE: &str = "org.freedesktop.NetworkManager.AccessPoint";
const SETTINGS_IFACE: &str = "org.freedesktop.NetworkManager.Settings";
const CONNECTION_IFACE: &str = "org.freedesktop.NetworkManager.Settings.Connection";
const ACTIVE_IFACE: &str = "org.freedesktop.NetworkManager.Connection.Active";

const DEVICE_TYPE_WIFI: u32 = 2;
const DEVICE_TYPE_ETHERNET: u32 = 1;

type Settings = HashMap<String, HashMap<String, OwnedValue>>;

/// Internal helper -- one active connection's identity, enough to
/// correctly resolve both the "is this saved profile active" question
/// (§6.1) and the "what's the real active SSID" question (§6.2).
struct ActiveConn {
    conn_type: String,
    id: String,
    /// The underlying Settings/N path (Connection.Active's `Connection`
    /// property), NOT the ActiveConnection/N path itself.
    settings_path: String,
}

#[derive(Clone)]
pub struct NetworkManager {
    conn: Connection,
}

impl NetworkManager {
    pub async fn new() -> zbus::Result<Self> {
        let conn = Connection::system().await?;
        Ok(Self { conn })
    }

    // ---- generic D-Bus property helpers -----------------------------
    // Replace ~30 hand-written Properties.Get/Set blocks in Orbit's
    // version of this file with one pair of helpers.

    async fn get_prop(&self, path: &str, iface: &str, name: &str) -> zbus::Result<OwnedValue> {
        self.conn
            .call_method(Some(NM), path, Some(PROPS_IFACE), "Get", &(iface, name))
            .await?
            .body()
            .deserialize::<OwnedValue>()
    }

    async fn set_prop(&self, path: &str, iface: &str, name: &str, value: Value<'_>) -> zbus::Result<()> {
        self.conn
            .call_method(Some(NM), path, Some(PROPS_IFACE), "Set", &(iface, name, value))
            .await?;
        Ok(())
    }

    async fn prop_u32(&self, path: &str, iface: &str, name: &str) -> u32 {
        self.get_prop(path, iface, name)
            .await
            .ok()
            .and_then(|v| u32::try_from(Value::from(v)).ok())
            .unwrap_or(0)
    }

    /// AccessPoint's `Strength` is a D-Bus BYTE (`y`), not a u32 -- using
    /// `prop_u32` there silently returned 0 for every AP (the `u32::
    /// try_from(Value::U8(_))` conversion fails, `.unwrap_or(0)` masked
    /// it), confirmed live against `nmcli`'s real signal percentages.
    async fn prop_u8(&self, path: &str, iface: &str, name: &str) -> u8 {
        self.get_prop(path, iface, name)
            .await
            .ok()
            .and_then(|v| u8::try_from(Value::from(v)).ok())
            .unwrap_or(0)
    }

    async fn prop_bool(&self, path: &str, iface: &str, name: &str) -> bool {
        self.get_prop(path, iface, name)
            .await
            .ok()
            .and_then(|v| bool::try_from(Value::from(v)).ok())
            .unwrap_or(false)
    }

    async fn prop_string(&self, path: &str, iface: &str, name: &str) -> String {
        self.get_prop(path, iface, name)
            .await
            .ok()
            .and_then(|v| String::try_from(Value::from(v)).ok())
            .unwrap_or_default()
    }

    /// Returns None for the NM convention of "/" meaning "no object".
    async fn prop_path(&self, path: &str, iface: &str, name: &str) -> Option<OwnedObjectPath> {
        let v = self.get_prop(path, iface, name).await.ok()?;
        let p = OwnedObjectPath::try_from(Value::from(v)).ok()?;
        if p.as_str() == "/" {
            None
        } else {
            Some(p)
        }
    }

    // ---- radio --------------------------------------------------------

    pub async fn is_wifi_enabled(&self) -> zbus::Result<bool> {
        let v = self.get_prop(NM_PATH, NM_IFACE, "WirelessEnabled").await?;
        bool::try_from(v).map_err(zbus::Error::from)
    }

    pub async fn set_wifi_enabled(&self, enabled: bool) -> zbus::Result<()> {
        self.set_prop(NM_PATH, NM_IFACE, "WirelessEnabled", Value::Bool(enabled)).await
    }

    // ---- devices --------------------------------------------------------

    pub async fn wireless_devices(&self) -> zbus::Result<Vec<String>> {
        let devices: Vec<OwnedObjectPath> = self
            .conn
            .call_method(Some(NM), NM_PATH, Some(NM_IFACE), "GetDevices", &())
            .await?
            .body()
            .deserialize()?;

        let mut wireless = Vec::new();
        for path in devices {
            let dtype = self.prop_u32(path.as_str(), DEVICE_IFACE, "DeviceType").await;
            if dtype == DEVICE_TYPE_WIFI {
                wireless.push(path.to_string());
            }
        }
        Ok(wireless)
    }

    pub async fn wifi_device_state(&self) -> zbus::Result<u32> {
        let devices = self.wireless_devices().await?;
        if let Some(path) = devices.first() {
            return Ok(self.prop_u32(path, DEVICE_IFACE, "State").await);
        }
        Ok(0)
    }

    // ---- scan / list ----------------------------------------------------

    pub async fn request_scan(&self) -> zbus::Result<()> {
        for device_path in self.wireless_devices().await? {
            let path: ObjectPath = device_path
                .as_str()
                .try_into()
                .map_err(|e: zbus::zvariant::Error| zbus::Error::Variant(e))?;
            self.conn
                .call_method(
                    Some(NM),
                    &path,
                    Some(WIRELESS_IFACE),
                    "RequestScan",
                    &HashMap::<String, Value>::new(),
                )
                .await?;
        }
        Ok(())
    }

    pub async fn access_points(&self) -> zbus::Result<Vec<AccessPoint>> {
        let devices = self.wireless_devices().await?;
        let active_ssid = self.active_wifi_ssid().await;
        let saved = self.wifi_saved_ssids().await;

        let mut access_points = Vec::new();

        for device_path in devices {
            let path: ObjectPath = device_path
                .as_str()
                .try_into()
                .map_err(|e: zbus::zvariant::Error| zbus::Error::Variant(e))?;
            let ap_paths: Vec<OwnedObjectPath> = self
                .conn
                .call_method(Some(NM), &path, Some(WIRELESS_IFACE), "GetAllAccessPoints", &())
                .await?
                .body()
                .deserialize()?;

            for ap_path in ap_paths {
                if ap_path.as_str() == "/" {
                    continue;
                }

                let ssid_owned = self.get_prop(ap_path.as_str(), AP_IFACE, "Ssid").await;
                let ssid_bytes = ssid_owned.ok().map(owned_value_to_bytes).unwrap_or_default();
                let ssid = String::from_utf8_lossy(&ssid_bytes).to_string();
                if ssid.is_empty() {
                    continue;
                }

                let strength = self.prop_u8(ap_path.as_str(), AP_IFACE, "Strength").await;
                let flags = self.prop_u32(ap_path.as_str(), AP_IFACE, "Flags").await;
                let wpa_flags = self.prop_u32(ap_path.as_str(), AP_IFACE, "WpaFlags").await;
                let rsn_flags = self.prop_u32(ap_path.as_str(), AP_IFACE, "RsnFlags").await;
                let security = SecurityType::from_flags(flags, wpa_flags, rsn_flags);

                let is_connected = active_ssid.as_deref() == Some(ssid.as_str());
                let is_saved = saved.contains(&ssid);

                access_points.push(AccessPoint {
                    ssid,
                    signal: strength,
                    security,
                    is_connected,
                    is_saved,
                    device_path: device_path.clone(),
                    ap_path: ap_path.to_string(),
                });
            }
        }

        // Dedupe by SSID, keeping the strongest signal; if a duplicate was
        // the connected one, propagate is_connected onto the kept entry.
        access_points.sort_by(|a, b| b.signal.cmp(&a.signal));
        let mut seen: std::collections::HashSet<String> = std::collections::HashSet::new();
        let mut unique: Vec<AccessPoint> = Vec::new();
        for ap in access_points {
            if !seen.contains(&ap.ssid) {
                seen.insert(ap.ssid.clone());
                unique.push(ap);
            } else if ap.is_connected {
                if let Some(existing) = unique.iter_mut().find(|x| x.ssid == ap.ssid) {
                    existing.is_connected = true;
                }
            }
        }
        Ok(unique)
    }

    // ---- active connection / saved profiles ------------------------------

    async fn active_connection_paths(&self) -> Vec<OwnedObjectPath> {
        match self.get_prop(NM_PATH, NM_IFACE, "ActiveConnections").await {
            Ok(v) => Vec::<OwnedObjectPath>::try_from(Value::from(v)).unwrap_or_default(),
            Err(_) => Vec::new(),
        }
    }

    /// One D-Bus round trip per active connection, giving both
    /// `active_wifi_ssid()` and `saved_networks()`'s `is_active` a
    /// correct `Connection.Active.Connection` (the underlying Settings
    /// path) to compare against -- the piece Orbit's own
    /// `get_saved_networks` skips (project plan §6.1).
    async fn active_connections(&self) -> Vec<ActiveConn> {
        let mut out = Vec::new();
        for path in self.active_connection_paths().await {
            let p = path.as_str();
            let conn_type = self.prop_string(p, ACTIVE_IFACE, "Type").await;
            let id = self.prop_string(p, ACTIVE_IFACE, "Id").await;
            let settings_path = self
                .prop_path(p, ACTIVE_IFACE, "Connection")
                .await
                .map(|op| op.to_string())
                .unwrap_or_default();
            out.push(ActiveConn { conn_type, id, settings_path });
        }
        out
    }

    /// The real SSID of the active WiFi connection (project plan §6.2 --
    /// Orbit's `get_active_ssid` returns the connection's renameable `Id`
    /// label instead, which mismatches every scanned AP once a profile
    /// has been renamed). Falls back to `Id` if the settings lookup fails
    /// for any reason, so callers still get *something* useful.
    pub async fn active_wifi_ssid(&self) -> Option<String> {
        for ac in self.active_connections().await {
            if ac.conn_type != "802-11-wireless" && ac.conn_type != "802-3-ethernet" {
                continue;
            }
            let lower_id = ac.id.to_lowercase();
            if lower_id.starts_with("docker")
                || lower_id.starts_with("br-")
                || lower_id.starts_with("veth")
                || lower_id.starts_with("lo")
                || lower_id.starts_with("virbr")
            {
                continue;
            }

            if ac.conn_type == "802-11-wireless" && !ac.settings_path.is_empty() {
                if let Ok(settings) = self.get_connection_settings(&ac.settings_path).await {
                    if let Some(ssid) = ssid_from_settings(&settings) {
                        return Some(ssid);
                    }
                }
            }
            return Some(ac.id);
        }
        None
    }

    async fn get_connection_settings(&self, path: &str) -> zbus::Result<Settings> {
        let path_obj: ObjectPath = path.try_into().map_err(|e: zbus::zvariant::Error| zbus::Error::Variant(e))?;
        self.conn
            .call_method(Some(NM), &path_obj, Some(CONNECTION_IFACE), "GetSettings", &())
            .await?
            .body()
            .deserialize()
    }

    /// All WiFi profiles (saved connections), used both to answer
    /// "is this SSID already saved" for `access_points()` and as the
    /// basis for `saved_networks()`.
    async fn wifi_profiles(&self) -> zbus::Result<Vec<(String, Settings)>> {
        let paths: Vec<OwnedObjectPath> = self
            .conn
            .call_method(Some(NM), NM_SETTINGS_PATH, Some(SETTINGS_IFACE), "ListConnections", &())
            .await?
            .body()
            .deserialize()?;

        let mut out = Vec::new();
        for path in paths {
            if let Ok(settings) = self.get_connection_settings(path.as_str()).await {
                let conn_type = settings
                    .get("connection")
                    .and_then(|c| c.get("type"))
                    .and_then(|v| <&str>::try_from(&**v).ok())
                    .unwrap_or_default();
                if conn_type == "802-11-wireless" {
                    out.push((path.to_string(), settings));
                }
            }
        }
        Ok(out)
    }

    async fn wifi_saved_ssids(&self) -> std::collections::HashSet<String> {
        self.wifi_profiles()
            .await
            .unwrap_or_default()
            .iter()
            .filter_map(|(_, s)| ssid_from_settings(s))
            .collect()
    }

    pub async fn saved_networks(&self) -> zbus::Result<Vec<SavedNetwork>> {
        let profiles = self.wifi_profiles().await?;
        let active = self.active_connections().await;

        let mut out = Vec::new();
        for (settings_path, settings) in profiles {
            let connection = match settings.get("connection") {
                Some(c) => c,
                None => continue,
            };
            let id = connection
                .get("id")
                .and_then(|v| <&str>::try_from(&**v).ok())
                .unwrap_or_default()
                .to_string();
            let autoconnect = connection
                .get("autoconnect")
                .and_then(|v| bool::try_from(&**v).ok())
                .unwrap_or(true);
            let ssid = ssid_from_settings(&settings).unwrap_or_else(|| id.clone());

            // §6.1 fix: compare against the active connections' resolved
            // settings_path (Connection.Active.Connection), not against
            // the ActiveConnection/N paths themselves.
            let is_active = active.iter().any(|ac| ac.settings_path == settings_path);

            out.push(SavedNetwork { ssid, id, settings_path, autoconnect, is_active });
        }

        out.sort_by(|a, b| b.is_active.cmp(&a.is_active).then_with(|| a.ssid.cmp(&b.ssid)));
        Ok(out)
    }

    async fn find_profile_by_ssid(&self, ssid: &str) -> Option<String> {
        for (path, settings) in self.wifi_profiles().await.ok()?.into_iter() {
            if let Some(stored) = ssid_from_settings(&settings) {
                if stored == ssid || stored.trim() == ssid.trim() {
                    return Some(path);
                }
            }
            if let Some(id) = settings
                .get("connection")
                .and_then(|c| c.get("id"))
                .and_then(|v| <&str>::try_from(&**v).ok())
            {
                if id == ssid || id.trim() == ssid.trim() {
                    return Some(path);
                }
            }
        }
        None
    }

    // ---- mutations --------------------------------------------------------

    /// Adapted from network_manager.rs:462-531. Reuses an existing saved
    /// profile via ActivateConnection (password ignored -- NM reuses the
    /// stored secret); otherwise builds a new profile via
    /// AddAndActivateConnection. See this module's header comment for the
    /// WPA2-PSK-only documented gap.
    pub async fn connect(&self, ssid: &str, password: Option<&str>, device_path: &str) -> zbus::Result<()> {
        let dev_path: ObjectPath = device_path.try_into().map_err(|e: zbus::zvariant::Error| zbus::Error::Variant(e))?;
        let specific_object: ObjectPath = "/".try_into().unwrap();

        if let Some(existing) = self.find_profile_by_ssid(ssid).await {
            let existing_path: ObjectPath = existing.as_str().try_into().map_err(|e: zbus::zvariant::Error| zbus::Error::Variant(e))?;
            self.conn
                .call_method(
                    Some(NM),
                    NM_PATH,
                    Some(NM_IFACE),
                    "ActivateConnection",
                    &(&existing_path, &dev_path, &specific_object),
                )
                .await?;
        } else {
            let config = build_wifi_connection_dict(ssid, password, false);
            self.conn
                .call_method(
                    Some(NM),
                    NM_PATH,
                    Some(NM_IFACE),
                    "AddAndActivateConnection",
                    &(&config, &dev_path, &specific_object),
                )
                .await?;
        }

        // Poll for confirmation, up to 15s, same as Orbit.
        for _ in 0..30 {
            tokio::time::sleep(tokio::time::Duration::from_millis(500)).await;
            if self.active_wifi_ssid().await.as_deref() == Some(ssid) {
                return Ok(());
            }
        }
        Err(zbus::Error::Address("Connection timeout".to_string()))
    }

    /// Adapted from network_manager.rs:533-580. Always creates a new
    /// profile (never reuses one), no confirmation poll -- matching
    /// Orbit's behavior for hidden networks.
    pub async fn connect_hidden(&self, ssid: &str, password: Option<&str>, device_path: &str) -> zbus::Result<()> {
        let dev_path: ObjectPath = device_path.try_into().map_err(|e: zbus::zvariant::Error| zbus::Error::Variant(e))?;
        let specific_object: ObjectPath = "/".try_into().unwrap();
        let config = build_wifi_connection_dict(ssid, password, true);
        self.conn
            .call_method(
                Some(NM),
                NM_PATH,
                Some(NM_IFACE),
                "AddAndActivateConnection",
                &(&config, &dev_path, &specific_object),
            )
            .await?;
        Ok(())
    }

    pub async fn disconnect(&self, ssid: &str) -> zbus::Result<()> {
        for path in self.active_connection_paths().await {
            let id = self.prop_string(path.as_str(), ACTIVE_IFACE, "Id").await;
            if id == ssid {
                self.conn
                    .call_method(Some(NM), NM_PATH, Some(NM_IFACE), "DeactivateConnection", &(&path))
                    .await?;
                return Ok(());
            }
        }
        Ok(())
    }

    pub async fn forget(&self, settings_path: &str) -> zbus::Result<()> {
        let path_obj: ObjectPath = settings_path.try_into().map_err(|e: zbus::zvariant::Error| zbus::Error::Variant(e))?;
        self.conn
            .call_method(Some(NM), &path_obj, Some(CONNECTION_IFACE), "Delete", &())
            .await?;
        Ok(())
    }

    /// Read-modify-write of the whole settings dict (there's no `Set` on
    /// a single setting key) -- adapted from network_manager.rs:1360-1387.
    /// GetSettings never returns secrets, so the PSK is absent from the
    /// dict written back; NM keeps the on-disk secret since the security
    /// group's other keys survive. Verify this holds (project plan §6.5,
    /// Phase 1a checklist item 20) before relying on it in the UI.
    pub async fn set_autoconnect(&self, settings_path: &str, autoconnect: bool) -> zbus::Result<()> {
        let path_obj: ObjectPath = settings_path.try_into().map_err(|e: zbus::zvariant::Error| zbus::Error::Variant(e))?;
        let current = self.get_connection_settings(settings_path).await?;

        let mut new_settings: HashMap<String, HashMap<String, Value>> = HashMap::new();
        for (group_name, group_settings) in current {
            let mut new_group: HashMap<String, Value> = HashMap::new();
            for (key, value) in group_settings {
                new_group.insert(key, Value::from(value));
            }
            new_settings.insert(group_name, new_group);
        }
        if let Some(conn_group) = new_settings.get_mut("connection") {
            conn_group.insert("autoconnect".to_string(), Value::Bool(autoconnect));
        }

        self.conn
            .call_method(Some(NM), &path_obj, Some(CONNECTION_IFACE), "Update", &(&new_settings))
            .await?;
        Ok(())
    }

    // ---- wired / ethernet (Phase 2) --------------------------------------

    pub async fn wired_devices(&self) -> zbus::Result<Vec<String>> {
        let devices: Vec<OwnedObjectPath> = self
            .conn
            .call_method(Some(NM), NM_PATH, Some(NM_IFACE), "GetDevices", &())
            .await?
            .body()
            .deserialize()?;

        let mut wired = Vec::new();
        for path in devices {
            let dtype = self.prop_u32(path.as_str(), DEVICE_IFACE, "DeviceType").await;
            if dtype == DEVICE_TYPE_ETHERNET {
                wired.push(path.to_string());
            }
        }
        Ok(wired)
    }

    /// Adapted from network_manager.rs:1047-1305, restructured around the
    /// prop_* helpers. Per wired device: read live state off
    /// `Device`/`Connection.Active`/`IP4Config` if there's an active
    /// connection; otherwise fall back to scanning Settings for a
    /// `802-3-ethernet` profile whose `interface-name` matches, same as
    /// Orbit.
    pub async fn wired_profiles(&self) -> zbus::Result<Vec<WiredProfile>> {
        let mut profiles = Vec::new();

        for device_path in self.wired_devices().await? {
            let iface = self.prop_string(&device_path, DEVICE_IFACE, "Interface").await;
            let iface = if iface.is_empty() { "Unknown".to_string() } else { iface };
            let has_carrier = self.prop_bool(&device_path, DEVICE_IFACE, "Carrier").await;
            let speed = self.prop_u32(&device_path, DEVICE_IFACE, "Speed").await;
            let mac_address = self.prop_string(&device_path, DEVICE_IFACE, "HwAddress").await;
            let active_path = self.prop_path(&device_path, DEVICE_IFACE, "ActiveConnection").await;

            let mut name = iface.clone();
            let mut connection_path = String::new();
            let mut autoconnect = true;
            let mut is_active = false;
            let mut ip4_address = String::new();
            let mut gateway = String::new();
            let mut dns_servers = Vec::new();

            if let Some(ref active) = active_path {
                is_active = true;
                let id = self.prop_string(active.as_str(), ACTIVE_IFACE, "Id").await;
                if !id.is_empty() {
                    name = id;
                }
                if let Some(conn) = self.prop_path(active.as_str(), ACTIVE_IFACE, "Connection").await {
                    connection_path = conn.to_string();
                }
                if let Some(ip4_path) = self.prop_path(active.as_str(), ACTIVE_IFACE, "Ip4Config").await {
                    ip4_address = self.first_address(ip4_path.as_str(), "org.freedesktop.NetworkManager.IP4Config", "AddressData").await;
                    gateway = self.prop_string(ip4_path.as_str(), "org.freedesktop.NetworkManager.IP4Config", "Gateway").await;
                    dns_servers = self
                        .address_list(ip4_path.as_str(), "org.freedesktop.NetworkManager.IP4Config", "NameserverData")
                        .await;
                }
            }

            if connection_path.is_empty() {
                // No active connection -- look for a saved 802-3-ethernet
                // profile bound to this interface, matching Orbit's
                // fallback.
                if let Ok(paths) = self.list_connections().await {
                    for path in paths {
                        if let Ok(settings) = self.get_connection_settings(path.as_str()).await {
                            let Some(connection) = settings.get("connection") else { continue };
                            let conn_type = connection.get("type").and_then(|v| <&str>::try_from(&**v).ok()).unwrap_or_default();
                            if conn_type != "802-3-ethernet" {
                                continue;
                            }
                            let interface_name =
                                connection.get("interface-name").and_then(|v| <&str>::try_from(&**v).ok()).unwrap_or_default();
                            if interface_name != iface {
                                continue;
                            }
                            connection_path = path;
                            if let Some(id) = connection.get("id").and_then(|v| <&str>::try_from(&**v).ok()) {
                                name = id.to_string();
                            }
                            autoconnect = connection.get("autoconnect").and_then(|v| bool::try_from(&**v).ok()).unwrap_or(true);
                            break;
                        }
                    }
                }
            } else if let Ok(settings) = self.get_connection_settings(&connection_path).await {
                if let Some(connection) = settings.get("connection") {
                    autoconnect = connection.get("autoconnect").and_then(|v| bool::try_from(&**v).ok()).unwrap_or(true);
                }
            }

            profiles.push(WiredProfile {
                name,
                device_name: iface,
                device_path,
                connection_path,
                is_active,
                has_carrier,
                speed,
                mac_address,
                ip4_address,
                gateway,
                dns_servers,
                autoconnect,
            });
        }

        Ok(profiles)
    }

    pub async fn activate_wired(&self, connection_path: &str, device_path: &str) -> zbus::Result<()> {
        let conn_path: ObjectPath = connection_path.try_into().map_err(|e: zbus::zvariant::Error| zbus::Error::Variant(e))?;
        let dev_path: ObjectPath = device_path.try_into().map_err(|e: zbus::zvariant::Error| zbus::Error::Variant(e))?;
        let specific: ObjectPath = "/".try_into().unwrap();
        self.conn
            .call_method(Some(NM), NM_PATH, Some(NM_IFACE), "ActivateConnection", &(&conn_path, &dev_path, &specific))
            .await?;
        Ok(())
    }

    pub async fn deactivate_wired(&self, device_path: &str) -> zbus::Result<()> {
        if let Some(active) = self.prop_path(device_path, DEVICE_IFACE, "ActiveConnection").await {
            self.conn
                .call_method(Some(NM), NM_PATH, Some(NM_IFACE), "DeactivateConnection", &(&active))
                .await?;
        }
        Ok(())
    }

    async fn list_connections(&self) -> zbus::Result<Vec<String>> {
        let paths: Vec<OwnedObjectPath> = self
            .conn
            .call_method(Some(NM), NM_SETTINGS_PATH, Some(SETTINGS_IFACE), "ListConnections", &())
            .await?
            .body()
            .deserialize()?;
        Ok(paths.into_iter().map(|p| p.to_string()).collect())
    }

    /// Reads an `aa{sv}` property (NetworkManager's AddressData/
    /// NameserverData shape) and returns every entry's "address" key --
    /// adapted from the byte-for-byte identical extraction idiom repeated
    /// throughout network_manager.rs:1148-1207/1440-1560.
    async fn address_list(&self, path: &str, iface: &str, name: &str) -> Vec<String> {
        let Ok(owned) = self.get_prop(path, iface, name).await else { return Vec::new() };
        let val: Value = Value::from(owned);
        let Value::Array(array) = val else { return Vec::new() };

        array
            .iter()
            .filter_map(|entry| {
                let owned_entry = OwnedValue::try_from(entry).ok()?;
                let map = HashMap::<String, OwnedValue>::try_from(owned_entry).ok()?;
                let addr = map.get("address")?;
                <&str>::try_from(&**addr).ok().map(|s| s.to_string())
            })
            .collect()
    }

    async fn first_address(&self, path: &str, iface: &str, name: &str) -> String {
        self.address_list(path, iface, name).await.into_iter().next().unwrap_or_default()
    }
}

/// Extracts the real SSID (802-11-wireless.ssid, stored as raw bytes) out
/// of a connection's settings dict, adapted from the byte-extraction idiom
/// used throughout orbit-vendor/src/dbus/network_manager.rs (e.g.
/// find_connection_by_ssid:428-435).
fn ssid_from_settings(settings: &Settings) -> Option<String> {
    let wireless = settings.get("802-11-wireless")?;
    let v = wireless.get("ssid")?;
    let bytes = owned_ref_to_bytes(v);
    if bytes.is_empty() {
        None
    } else {
        Some(String::from_utf8_lossy(&bytes).to_string())
    }
}

fn owned_ref_to_bytes(v: &OwnedValue) -> Vec<u8> {
    if let Value::Array(a) = &**v {
        a.iter().filter_map(|iv| u8::try_from(iv).ok()).collect()
    } else {
        Vec::new()
    }
}

fn owned_value_to_bytes(v: OwnedValue) -> Vec<u8> {
    let val: Value = v.into();
    if let Value::Array(a) = val {
        a.iter().filter_map(|iv| u8::try_from(iv).ok()).collect()
    } else {
        Vec::new()
    }
}

/// Builds the nested `a{sa{sv}}` connection dict for
/// AddAndActivateConnection, shared by `connect()` (new-profile branch)
/// and `connect_hidden()` -- adapted from network_manager.rs:477-506 and
/// :534-563 (identical shape, `hidden` is the only difference).
fn build_wifi_connection_dict<'a>(
    ssid: &'a str,
    password: Option<&'a str>,
    hidden: bool,
) -> HashMap<&'static str, HashMap<&'static str, Value<'a>>> {
    let mut connection: HashMap<&str, Value> = HashMap::new();
    connection.insert("type", "802-11-wireless".into());
    connection.insert("id", ssid.into());
    connection.insert("uuid", Value::Str(uuid::Uuid::new_v4().to_string().into()));
    connection.insert("autoconnect", true.into());

    let mut wireless: HashMap<&str, Value> = HashMap::new();
    wireless.insert("ssid", ssid.as_bytes().into());
    wireless.insert("mode", "infrastructure".into());
    if hidden {
        wireless.insert("hidden", true.into());
    }

    let mut config: HashMap<&str, HashMap<&str, Value>> = HashMap::new();
    config.insert("connection", connection);
    config.insert("802-11-wireless", wireless);

    // WPA2-personal only -- see this module's header comment (project
    // plan §6.3) for the documented WPA3-SAE/enterprise gap.
    if let Some(pwd) = password {
        let mut wsec: HashMap<&str, Value> = HashMap::new();
        wsec.insert("key-mgmt", "wpa-psk".into());
        wsec.insert("auth-alg", "open".into());
        wsec.insert("psk", pwd.into());
        config.insert("802-11-wireless-security", wsec);
    }

    let mut ipv4: HashMap<&str, Value> = HashMap::new();
    ipv4.insert("method", "auto".into());
    config.insert("ipv4", ipv4);

    let mut ipv6: HashMap<&str, Value> = HashMap::new();
    ipv6.insert("method", "ignore".into());
    config.insert("ipv6", ipv6);

    config
}
