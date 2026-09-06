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
//! The §6.3 gap is CLOSED: `build_security_groups` now writes the right
//! `key-mgmt` per `SecurityType` (`wpa-psk` / `sae` / `wpa-eap` /
//! `wpa-eap-suite-b-192` / WEP's `none`) and, for the enterprise cases,
//! the whole `802-1x` group (EAP method, identity, anonymous identity,
//! phase-2 auth) from the credentials the user typed -- so an eduroam-shaped
//! network can be joined from scratch, not just reactivated from an
//! existing profile.
//!
//! One deliberate omission there: no `802-1x.ca-cert` /
//! `domain-suffix-match` is written. Balise has no UI to pick a
//! certificate file, and NM joins without one (wpa_supplicant logs the
//! connection as unvalidated). That is the same trade-off `nmcli
//! device wifi connect` makes.

use std::collections::HashMap;
use zbus::zvariant::{ObjectPath, OwnedObjectPath, OwnedValue, Value};
use zbus::Connection;

use super::types::{AccessPoint, SavedNetwork, SecurityType, WifiCredentials, WifiDetails, WiredProfile};

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
const IP4_IFACE: &str = "org.freedesktop.NetworkManager.IP4Config";
const IP6_IFACE: &str = "org.freedesktop.NetworkManager.IP6Config";

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

    /// Adapted from network_manager.rs:462-531, then extended for
    /// credential entry.
    ///
    /// Three branches, not the original two:
    /// - a saved profile and NO new credentials -> plain
    ///   ActivateConnection, NM reuses the stored secret (unchanged);
    /// - a saved profile and new credentials -> `update_wifi_security`
    ///   rewrites just the security groups, THEN activate. This is the
    ///   "the saved password is wrong / the campus rotated it" path; it
    ///   deliberately keeps the rest of the profile (autoconnect, IP
    ///   config, renamed id) instead of deleting and recreating it;
    /// - no profile -> AddAndActivateConnection, now with the right
    ///   `key-mgmt` and, for enterprise, a real `802-1x` group.
    pub async fn connect(
        &self,
        ssid: &str,
        security: &SecurityType,
        creds: Option<&WifiCredentials>,
        device_path: &str,
    ) -> zbus::Result<()> {
        let dev_path: ObjectPath = device_path.try_into().map_err(|e: zbus::zvariant::Error| zbus::Error::Variant(e))?;
        let specific_object: ObjectPath = "/".try_into().unwrap();
        let has_creds = matches!(creds, Some(c) if !c.is_empty());

        // An 802.1X profile with no username is invalid, and NM rejects it
        // with a D-Bus error whose text says nothing a user could act on.
        // The form asks for both fields, so this only fires for a caller
        // that skipped it -- but it fires with a message worth reading.
        if security.is_enterprise() && has_creds && creds.map_or(true, |c| c.identity.is_empty()) {
            return Err(zbus::Error::Failure(
                "This network needs a username as well as a password".to_string(),
            ));
        }

        let active_path: Option<String> = if let Some(existing) = self.find_profile_by_ssid(ssid).await {
            if has_creds {
                self.update_wifi_security(&existing, security, creds.unwrap()).await?;
            }
            let existing_path: ObjectPath = existing.as_str().try_into().map_err(|e: zbus::zvariant::Error| zbus::Error::Variant(e))?;
            self.conn
                .call_method(
                    Some(NM),
                    NM_PATH,
                    Some(NM_IFACE),
                    "ActivateConnection",
                    &(&existing_path, &dev_path, &specific_object),
                )
                .await?
                .body()
                .deserialize::<OwnedObjectPath>()
                .ok()
                .map(|p| p.to_string())
        } else {
            let config = build_wifi_connection_dict(ssid, security, creds, false);
            self.conn
                .call_method(
                    Some(NM),
                    NM_PATH,
                    Some(NM_IFACE),
                    "AddAndActivateConnection",
                    &(&config, &dev_path, &specific_object),
                )
                .await?
                .body()
                // AddAndActivateConnection returns (settings_path,
                // active_path) -- only the second is of interest here.
                .deserialize::<(OwnedObjectPath, OwnedObjectPath)>()
                .ok()
                .map(|(_, active)| active.to_string())
        };

        // Poll for confirmation, up to 15s, same as Orbit -- but watching
        // the ActiveConnection's own State alongside the active SSID, so a
        // rejected credential reports itself in a second or two instead of
        // spending the full 15s pretending to still be connecting. That
        // difference is the whole point of a password form: "wrong
        // password" has to come back while the field is still on screen.
        for _ in 0..30 {
            tokio::time::sleep(tokio::time::Duration::from_millis(500)).await;
            if self.active_wifi_ssid().await.as_deref() == Some(ssid) {
                return Ok(());
            }
            if let Some(ref path) = active_path {
                // NM_ACTIVE_CONNECTION_STATE_DEACTIVATED. Reached when
                // authentication fails and NM gives up (it also deletes a
                // brand-new profile that never activated, which is why
                // nothing needs cleaning up here).
                if self.prop_u32(path, ACTIVE_IFACE, "State").await == 4 {
                    return Err(zbus::Error::Failure(if has_creds {
                        "Authentication failed \u{2014} check the credentials".to_string()
                    } else {
                        "Connection failed".to_string()
                    }));
                }
            }
        }
        Err(zbus::Error::Failure("Connection timeout".to_string()))
    }

    /// Replaces an existing profile's security groups wholesale with ones
    /// built from freshly typed credentials -- the read-modify-write shape
    /// `set_autoconnect` already uses, except the two security groups are
    /// DROPPED rather than copied through before the new ones go in. That
    /// matters for a network that changes kind (personal -> enterprise, or
    /// the reverse): a leftover `psk` next to a new `802-1x` group makes NM
    /// reject the whole profile as inconsistent.
    async fn update_wifi_security(
        &self,
        settings_path: &str,
        security: &SecurityType,
        creds: &WifiCredentials,
    ) -> zbus::Result<()> {
        let path_obj: ObjectPath = settings_path.try_into().map_err(|e: zbus::zvariant::Error| zbus::Error::Variant(e))?;
        let current = self.get_connection_settings(settings_path).await?;

        let mut new_settings: HashMap<String, HashMap<String, Value>> = HashMap::new();
        for (group_name, group_settings) in current {
            if group_name == "802-11-wireless-security" || group_name == "802-1x" {
                continue;
            }
            let mut new_group: HashMap<String, Value> = HashMap::new();
            for (key, value) in group_settings {
                new_group.insert(key, Value::from(value));
            }
            new_settings.insert(group_name, new_group);
        }
        for (name, group) in build_security_groups(security, Some(creds)) {
            new_settings.insert(
                name.to_string(),
                group.into_iter().map(|(k, v)| (k.to_string(), v)).collect(),
            );
        }

        self.conn
            .call_method(Some(NM), &path_obj, Some(CONNECTION_IFACE), "Update", &(&new_settings))
            .await?;
        Ok(())
    }

    /// Adapted from network_manager.rs:533-580. Always creates a new
    /// profile (never reuses one), no confirmation poll -- matching
    /// Orbit's behavior for hidden networks.
    pub async fn connect_hidden(
        &self,
        ssid: &str,
        security: &SecurityType,
        creds: Option<&WifiCredentials>,
        device_path: &str,
    ) -> zbus::Result<()> {
        let dev_path: ObjectPath = device_path.try_into().map_err(|e: zbus::zvariant::Error| zbus::Error::Variant(e))?;
        let specific_object: ObjectPath = "/".try_into().unwrap();
        let config = build_wifi_connection_dict(ssid, security, creds, true);
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
                    ip4_address = self.first_address(ip4_path.as_str(), IP4_IFACE, "AddressData").await;
                    gateway = self.prop_string(ip4_path.as_str(), IP4_IFACE, "Gateway").await;
                    dns_servers = self
                        .address_list(ip4_path.as_str(), IP4_IFACE, "NameserverData")
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

    /// Everything the WiFi detail page needs beyond the scanned
    /// `AccessPoint`. Two independent halves (see `WifiDetails`): the
    /// stored-profile half resolves for any saved network, the live half
    /// only when this SSID is the active connection.
    ///
    /// Not a port of orbit-vendor's `get_network_details` in shape, only
    /// in intent: that one is ~180 lines of hand-inlined
    /// `Properties.Get` + `Value::Array` walking repeated per field, and
    /// it identifies the active connection by comparing `Id == ssid`,
    /// which is exactly the renamed-profile bug the project plan's §6.2
    /// called out. This goes through the `prop_*`/`address_list` helpers
    /// and reuses `active_wifi_ssid()` (which resolves the real SSID out
    /// of the connection's settings) to decide whether we're the active
    /// one.
    pub async fn wifi_details(&self, ssid: &str) -> zbus::Result<WifiDetails> {
        let mut details = WifiDetails { ssid: ssid.to_string(), ..Default::default() };

        // ---- stored-profile half (works even when the network is down)
        if let Some(settings_path) = self.find_profile_by_ssid(ssid).await {
            if let Ok(settings) = self.get_connection_settings(&settings_path).await {
                details.autoconnect = settings
                    .get("connection")
                    .and_then(|c| c.get("autoconnect"))
                    .and_then(|v| bool::try_from(&**v).ok())
                    // NetworkManager omits `autoconnect` entirely when it
                    // holds its default, which is true -- a missing key
                    // means enabled, not disabled.
                    .unwrap_or(true);

                // Read back from what was actually stored rather than from
                // AP flags: this half of `wifi_details` is the half that
                // still resolves when the network is out of range and
                // there are no flags to read (see WifiDetails::security).
                let wsec = settings.get("802-11-wireless-security");
                let key_mgmt = wsec
                    .and_then(|g| g.get("key-mgmt"))
                    .and_then(|v| String::try_from(&**v).ok())
                    .unwrap_or_default();
                details.security = Some(match key_mgmt.as_str() {
                    "wpa-eap" => SecurityType::Enterprise,
                    "wpa-eap-suite-b-192" => SecurityType::Wpa3Enterprise,
                    "sae" => SecurityType::Wpa3,
                    "wpa-psk" => SecurityType::Wpa2,
                    // NM spells WEP as key-mgmt "none" plus a static key,
                    // which is also how a genuinely open profile with a
                    // (pointless) security group would look -- the key is
                    // what tells them apart.
                    "none" if wsec.map_or(false, |g| g.contains_key("wep-key0")) => SecurityType::Wep,
                    _ => SecurityType::None,
                });
            }
            details.settings_path = settings_path;
        }

        // ---- live half (only while this SSID is the active connection)
        if self.active_wifi_ssid().await.as_deref() != Some(ssid) {
            return Ok(details);
        }
        details.is_connected = true;

        for path in self.active_connection_paths().await {
            let p = path.as_str();
            if self.prop_string(p, ACTIVE_IFACE, "Type").await != "802-11-wireless" {
                continue;
            }

            if let Some(ip4) = self.prop_path(p, ACTIVE_IFACE, "Ip4Config").await {
                if ip4.as_str() != "/" {
                    details.ip4_address = self.first_address(ip4.as_str(), IP4_IFACE, "AddressData").await;
                    details.gateway = self.prop_string(ip4.as_str(), IP4_IFACE, "Gateway").await;
                    details.dns_servers = self.address_list(ip4.as_str(), IP4_IFACE, "NameserverData").await;
                }
            }

            if let Some(ip6) = self.prop_path(p, ACTIVE_IFACE, "Ip6Config").await {
                if ip6.as_str() != "/" {
                    details.ip6_address = self.first_address(ip6.as_str(), IP6_IFACE, "AddressData").await;
                }
            }
            break;
        }

        // MAC + link rate come off the device, not the connection. Using
        // `wireless_devices()` rather than walking Connection.Active's
        // `Devices` array (Orbit's route): the active WiFi connection is
        // by definition on a WiFi device, and this already-tested helper
        // saves an array-of-object-paths unwrap.
        if let Some(device) = self.wireless_devices().await.unwrap_or_default().first() {
            details.mac_address = self.prop_string(device, DEVICE_IFACE, "HwAddress").await;
            let bitrate = self.prop_u32(device, WIRELESS_IFACE, "Bitrate").await;
            if bitrate > 0 {
                details.speed = format!("{} Mb/s", bitrate / 1000);
            }
        }

        Ok(details)
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

/// The security half of a WiFi profile: the `802-11-wireless-security`
/// group, plus an `802-1x` group for the enterprise cases. Returned as a
/// list of (group name, group) pairs rather than folded straight into a
/// connection dict, because it has two callers with different shapes --
/// `build_wifi_connection_dict` (a brand-new profile) and
/// `update_wifi_security` (replacing these same groups on an existing
/// one, when the user re-types a password that had gone stale).
///
/// Empty for an open network, and for any network the user gave no
/// credentials for: NM then either joins it as open, or -- for a saved
/// profile being reactivated -- keeps whatever secrets it already has.
fn build_security_groups<'a>(
    security: &SecurityType,
    creds: Option<&'a WifiCredentials>,
) -> Vec<(&'static str, HashMap<&'static str, Value<'a>>)> {
    let creds = match creds {
        Some(c) if !c.is_empty() => c,
        _ => return Vec::new(),
    };
    if !security.needs_password() {
        return Vec::new();
    }

    let mut groups = Vec::new();
    let mut wsec: HashMap<&str, Value> = HashMap::new();

    match security {
        SecurityType::Enterprise | SecurityType::Wpa3Enterprise => {
            wsec.insert(
                "key-mgmt",
                if matches!(security, SecurityType::Wpa3Enterprise) {
                    "wpa-eap-suite-b-192".into()
                } else {
                    "wpa-eap".into()
                },
            );

            // "peap"/"mschapv2" is the eduroam-shaped default -- see
            // WifiCredentials' own field docs. `eap` is `as` (an array)
            // in NM's schema even though exactly one method is ever
            // written here.
            let eap = if creds.eap_method.is_empty() { "peap" } else { creds.eap_method.as_str() };
            let mut x8021: HashMap<&str, Value> = HashMap::new();
            x8021.insert("eap", Value::new(vec![eap.to_string()]));
            x8021.insert("identity", creds.identity.as_str().into());
            x8021.insert("password", creds.password.as_str().into());
            if !creds.anonymous_identity.is_empty() {
                x8021.insert("anonymous-identity", creds.anonymous_identity.as_str().into());
            }
            // EAP-PWD is a single-phase method: writing a phase2-auth for
            // it makes NM reject the profile outright.
            if eap != "pwd" {
                let phase2 = if creds.phase2_auth.is_empty() { "mschapv2" } else { creds.phase2_auth.as_str() };
                x8021.insert("phase2-auth", phase2.into());
            }

            groups.push(("802-11-wireless-security", wsec));
            groups.push(("802-1x", x8021));
        }
        SecurityType::Wpa3 => {
            // Same passphrase as WPA2, under SAE rather than PSK. This is
            // the bit the old code got wrong: it wrote `wpa-psk` for
            // every secured network, which a WPA3-only AP refuses.
            wsec.insert("key-mgmt", "sae".into());
            wsec.insert("psk", creds.password.as_str().into());
            groups.push(("802-11-wireless-security", wsec));
        }
        SecurityType::Wep => {
            // WEP has no key-mgmt of its own in NM's model -- it's
            // "none" (i.e. no WPA) plus a static key.
            wsec.insert("key-mgmt", "none".into());
            wsec.insert("auth-alg", "open".into());
            wsec.insert("wep-key0", creds.password.as_str().into());
            // 1 = NM_WEP_KEY_TYPE_KEY (a hex/ASCII key, what a WEP
            // network actually hands out, rather than a passphrase to
            // hash).
            wsec.insert("wep-key-type", Value::U32(1));
            groups.push(("802-11-wireless-security", wsec));
        }
        _ => {
            wsec.insert("key-mgmt", "wpa-psk".into());
            wsec.insert("auth-alg", "open".into());
            wsec.insert("psk", creds.password.as_str().into());
            groups.push(("802-11-wireless-security", wsec));
        }
    }

    groups
}

/// Builds the nested `a{sa{sv}}` connection dict for
/// AddAndActivateConnection, shared by `connect()` (new-profile branch)
/// and `connect_hidden()` -- adapted from network_manager.rs:477-506 and
/// :534-563 (identical shape, `hidden` is the only difference).
fn build_wifi_connection_dict<'a>(
    ssid: &'a str,
    security: &SecurityType,
    creds: Option<&'a WifiCredentials>,
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

    for (name, group) in build_security_groups(security, creds) {
        config.insert(name, group);
    }

    let mut ipv4: HashMap<&str, Value> = HashMap::new();
    ipv4.insert("method", "auto".into());
    config.insert("ipv4", ipv4);

    let mut ipv6: HashMap<&str, Value> = HashMap::new();
    ipv6.insert("method", "ignore".into());
    config.insert("ipv6", ipv6);

    config
}

/// Unit tests for `build_security_groups` only -- the one piece of this
/// module with real branching, and the one piece that cannot be exercised
/// against the hardware here: writing an 802.1X profile needs an
/// enterprise access point to aim at, and there isn't one on this network.
/// The shapes asserted below are NetworkManager's own settings schema
/// (`nm-settings-dbus(5)`, `802-11-wireless-security` and `802-1x`).
///
/// Everything else in this file is a D-Bus round trip that a unit test
/// could only assert against a mock of NM's own semantics -- the headless
/// `balise status|list|saved|wifi-details` probes exist for those.
#[cfg(test)]
mod tests {
    use super::*;

    fn creds(password: &str, identity: &str) -> WifiCredentials {
        WifiCredentials {
            password: password.to_string(),
            identity: identity.to_string(),
            ..Default::default()
        }
    }

    type Groups<'a> = Vec<(&'static str, HashMap<&'static str, Value<'a>>)>;

    fn group<'a, 'b>(groups: &'b Groups<'a>, name: &str) -> &'b HashMap<&'static str, Value<'a>> {
        &groups
            .iter()
            .find(|(n, _)| *n == name)
            .unwrap_or_else(|| panic!("expected a `{name}` group, got {:?}", groups.iter().map(|(n, _)| *n).collect::<Vec<_>>()))
            .1
    }

    fn text(g: &HashMap<&'static str, Value<'_>>, key: &str) -> String {
        match g.get(key) {
            Some(Value::Str(v)) => v.to_string(),
            other => panic!("`{key}`: expected a string, got {other:?}"),
        }
    }

    fn strings(g: &HashMap<&'static str, Value<'_>>, key: &str) -> Vec<String> {
        match g.get(key) {
            Some(Value::Array(a)) => a
                .iter()
                .map(|e| match e {
                    Value::Str(v) => v.to_string(),
                    other => panic!("`{key}`: expected strings, got {other:?}"),
                })
                .collect(),
            other => panic!("`{key}`: expected an array, got {other:?}"),
        }
    }

    #[test]
    fn open_network_gets_no_security_group() {
        assert!(build_security_groups(&SecurityType::None, Some(&creds("hunter2", ""))).is_empty());
    }

    #[test]
    fn no_credentials_means_no_security_group() {
        // The saved-profile reactivation path: NM keeps whatever secret it
        // already holds, and writing an empty psk over it would be the one
        // way to break a working profile.
        assert!(build_security_groups(&SecurityType::Wpa2, None).is_empty());
        assert!(build_security_groups(&SecurityType::Wpa2, Some(&WifiCredentials::default())).is_empty());
    }

    #[test]
    fn wpa2_writes_a_psk() {
        let c = creds("hunter2", "");
        let g = build_security_groups(&SecurityType::Wpa2, Some(&c));
        let wsec = group(&g, "802-11-wireless-security");
        assert_eq!(text(wsec, "key-mgmt"), "wpa-psk");
        assert_eq!(text(wsec, "psk"), "hunter2");
        assert!(g.iter().all(|(n, _)| *n != "802-1x"));
    }

    #[test]
    fn wpa3_writes_sae_not_psk() {
        // The bug this whole change set fixes at the personal end: every
        // secured network used to get `wpa-psk`, which a WPA3-only AP
        // refuses outright.
        let c = creds("hunter2", "");
        let g = build_security_groups(&SecurityType::Wpa3, Some(&c));
        let wsec = group(&g, "802-11-wireless-security");
        assert_eq!(text(wsec, "key-mgmt"), "sae");
        assert_eq!(text(wsec, "psk"), "hunter2");
    }

    #[test]
    fn wep_writes_a_static_key_not_a_psk() {
        let c = creds("0123456789", "");
        let g = build_security_groups(&SecurityType::Wep, Some(&c));
        let wsec = group(&g, "802-11-wireless-security");
        assert_eq!(text(wsec, "key-mgmt"), "none");
        assert_eq!(text(wsec, "wep-key0"), "0123456789");
        assert!(!wsec.contains_key("psk"));
    }

    #[test]
    fn enterprise_writes_an_802_1x_group() {
        let c = creds("hunter2", "lucas@univ.fr");
        let g = build_security_groups(&SecurityType::Enterprise, Some(&c));

        assert_eq!(text(group(&g, "802-11-wireless-security"), "key-mgmt"), "wpa-eap");

        let x = group(&g, "802-1x");
        // eduroam's defaults, applied when the form's EAP pickers are
        // left alone.
        assert_eq!(strings(x, "eap"), vec!["peap".to_string()]);
        assert_eq!(text(x, "identity"), "lucas@univ.fr");
        assert_eq!(text(x, "password"), "hunter2");
        assert_eq!(text(x, "phase2-auth"), "mschapv2");
        // Not written when the user left it blank -- an empty
        // anonymous-identity is not the same as none.
        assert!(!x.contains_key("anonymous-identity"));
    }

    #[test]
    fn enterprise_honours_the_pickers() {
        let c = WifiCredentials {
            password: "hunter2".to_string(),
            identity: "lucas@univ.fr".to_string(),
            anonymous_identity: "anonymous@univ.fr".to_string(),
            eap_method: "ttls".to_string(),
            phase2_auth: "pap".to_string(),
        };
        let g = build_security_groups(&SecurityType::Enterprise, Some(&c));
        let x = group(&g, "802-1x");
        assert_eq!(strings(x, "eap"), vec!["ttls".to_string()]);
        assert_eq!(text(x, "phase2-auth"), "pap");
        assert_eq!(text(x, "anonymous-identity"), "anonymous@univ.fr");
    }

    #[test]
    fn eap_pwd_has_no_phase_two() {
        // EAP-PWD is single-phase; NM rejects a profile that carries a
        // phase2-auth alongside it.
        let c = WifiCredentials {
            password: "hunter2".to_string(),
            identity: "lucas@univ.fr".to_string(),
            eap_method: "pwd".to_string(),
            phase2_auth: "mschapv2".to_string(),
            ..Default::default()
        };
        let g = build_security_groups(&SecurityType::Enterprise, Some(&c));
        assert!(!group(&g, "802-1x").contains_key("phase2-auth"));
    }

    #[test]
    fn wpa3_enterprise_uses_suite_b() {
        let c = creds("hunter2", "lucas@univ.fr");
        let g = build_security_groups(&SecurityType::Wpa3Enterprise, Some(&c));
        assert_eq!(
            text(group(&g, "802-11-wireless-security"), "key-mgmt"),
            "wpa-eap-suite-b-192"
        );
    }

    #[test]
    fn ap_flags_classify_enterprise_and_owe() {
        // Bit values from NM's NM80211ApSecurityFlags. The PSK/SAE pair is
        // already covered by this module's own header comment (read live
        // off real APs); these two are the ones added alongside credential
        // entry.
        //
        // 0x200 = KEY_MGMT_802_1X, 0x2000 = KEY_MGMT_EAP_SUITE_B_192,
        // 0x800 = KEY_MGMT_OWE, 0x400 = KEY_MGMT_SAE.
        assert_eq!(SecurityType::from_flags(1, 0, 0x188 | 0x200), SecurityType::Enterprise);
        assert_eq!(SecurityType::from_flags(1, 0, 0x2000), SecurityType::Wpa3Enterprise);
        // OWE is encrypted but credential-free -- it must not be offered a
        // password form.
        assert_eq!(SecurityType::from_flags(1, 0, 0x800), SecurityType::None);
        assert!(!SecurityType::from_flags(1, 0, 0x800).needs_password());
        // Unchanged classifications.
        assert_eq!(SecurityType::from_flags(1, 0, 0x488), SecurityType::Wpa3);
        assert_eq!(SecurityType::from_flags(1, 0, 0x188), SecurityType::Wpa2);
        assert_eq!(SecurityType::from_flags(0, 0, 0), SecurityType::None);
    }
}
