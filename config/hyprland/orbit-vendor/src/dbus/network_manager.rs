use zbus::Connection;
use std::collections::HashMap;

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct AccessPoint {
    pub ssid: String,
    pub signal_strength: u8,
    pub security: SecurityType,
    pub is_connected: bool,
    pub device_path: String,
    pub path: String,
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct SavedNetwork {
    pub ssid: String,
    pub path: String,
    pub autoconnect: bool,
    pub is_active: bool,
}

#[derive(Debug, Clone, Default, serde::Serialize, serde::Deserialize)]
pub struct NetworkDetails {
    pub ssid: String,
    pub ip4_address: String,
    pub ip6_address: String,
    pub gateway: String,
    pub ipv4_dns: Vec<String>,
    pub ipv6_dns: Vec<String>,
    pub mac_address: String,
    pub connection_speed: String,
    pub is_connected: bool,
}

#[derive(Debug, Clone, PartialEq, serde::Serialize, serde::Deserialize)]
pub enum SecurityType {
    None,
    WEP,
    WPA,
    WPA2,
    WPA3,
}

#[derive(Clone)]
pub struct NetworkManager {
    conn: Connection,
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct VpnProfile {
    pub name: String,
    pub vpn_type: String,
    pub path: String,
    pub is_active: bool,
    pub is_external: bool,
}

#[derive(Debug, Clone, Default, serde::Serialize, serde::Deserialize)]
pub struct WiredProfile {
    pub name: String,
    pub device_name: String,
    pub device_path: String,
    pub connection_path: String,
    pub is_active: bool,
    pub has_carrier: bool,
    pub speed: u32,
    pub mac_address: String,
    pub ip4_address: String,
    pub gateway: String,
    pub dns_servers: Vec<String>,
    pub autoconnect: bool,
}

impl NetworkManager {
    pub async fn new() -> zbus::Result<Self> {
        let conn = Connection::system().await?;
        Ok(Self { conn })
    }
    
    pub async fn is_wifi_enabled(&self) -> zbus::Result<bool> {
        let reply = self.conn
            .call_method(
                Some("org.freedesktop.NetworkManager"),
                "/org/freedesktop/NetworkManager",
                Some("org.freedesktop.DBus.Properties"),
                "Get",
                &("org.freedesktop.NetworkManager", "WirelessEnabled"),
            )
            .await?
            .body()
            .deserialize::<zbus::zvariant::OwnedValue>()?;
        
        bool::try_from(reply).map_err(zbus::Error::from)
    }
    
    pub async fn set_wifi_enabled(&self, enabled: bool) -> zbus::Result<()> {
        let value = zbus::zvariant::Value::Bool(enabled);
        self.conn
            .call_method(
                Some("org.freedesktop.NetworkManager"),
                "/org/freedesktop/NetworkManager",
                Some("org.freedesktop.DBus.Properties"),
                "Set",
                &("org.freedesktop.NetworkManager", "WirelessEnabled", value),
            )
            .await?;
        Ok(())
    }
    
    pub async fn check_connectivity(&self) -> zbus::Result<u32> {
        let reply = self.conn
            .call_method(
                Some("org.freedesktop.NetworkManager"),
                "/org/freedesktop/NetworkManager",
                Some("org.freedesktop.NetworkManager"),
                "CheckConnectivity",
                &(),
            )
            .await?
            .body()
            .deserialize::<u32>()?;
        Ok(reply)
    }
    
    pub async fn scan(&self) -> zbus::Result<()> {
        let devices = self.get_wireless_devices().await?;
        
        for device_path in devices {
            let path: zbus::zvariant::ObjectPath = device_path.as_str().try_into()
                .map_err(|e: zbus::zvariant::Error| zbus::Error::Variant(e))?;
            self.conn
                .call_method(
                    Some("org.freedesktop.NetworkManager"),
                    &path,
                    Some("org.freedesktop.NetworkManager.Device.Wireless"),
                    "RequestScan",
                    &HashMap::<String, zbus::zvariant::Value>::new(),
                )
                .await?;
        }
        
        Ok(())
    }
    
    pub async fn get_wifi_device_state(&self) -> zbus::Result<u32> {
        let devices = self.get_wireless_devices().await?;
        if let Some(device_path) = devices.get(0) {
            let path: zbus::zvariant::ObjectPath = device_path.as_str().try_into()
                .map_err(|e: zbus::zvariant::Error| zbus::Error::Variant(e))?;
            let reply = self.conn
                .call_method(
                    Some("org.freedesktop.NetworkManager"),
                    &path,
                    Some("org.freedesktop.DBus.Properties"),
                    "Get",
                    &("org.freedesktop.NetworkManager.Device", "State"),
                )
                .await?
                .body()
                .deserialize::<zbus::zvariant::OwnedValue>()?;
            
            let state: u32 = match u32::try_from(zbus::zvariant::Value::from(reply)) {
                Ok(t) => t,
                Err(_) => 0,
            };
            return Ok(state);
        }
        Ok(0)
    }

    pub async fn get_wireless_devices(&self) -> zbus::Result<Vec<String>> {
        let devices: Vec<zbus::zvariant::OwnedObjectPath> = self.conn
            .call_method(
                Some("org.freedesktop.NetworkManager"),
                "/org/freedesktop/NetworkManager",
                Some("org.freedesktop.NetworkManager"),
                "GetDevices",
                &(),
            )
            .await?
            .body()
            .deserialize()?;
        
        let mut wireless = Vec::new();
        
        for device_path in devices {
            let dtype_reply = self.conn
                .call_method(
                    Some("org.freedesktop.NetworkManager"),
                    &device_path,
                    Some("org.freedesktop.DBus.Properties"),
                    "Get",
                    &("org.freedesktop.NetworkManager.Device", "DeviceType"),
                )
                .await?
                .body()
                .deserialize::<zbus::zvariant::OwnedValue>()?;
            
            let device_type: u32 = match u32::try_from(zbus::zvariant::Value::from(dtype_reply)) {
                Ok(t) => t,
                Err(_) => 0,
            };
            
            if device_type == 2 {
                wireless.push(device_path.to_string());
            }
        }
        
        Ok(wireless)
    }
    
    pub async fn get_access_points(&self) -> zbus::Result<Vec<AccessPoint>> {
        let devices = self.get_wireless_devices().await?;
        let mut access_points = Vec::new();
        let active_ssid = self.get_active_ssid().await;
        
        for device_path in devices {
            let path: zbus::zvariant::ObjectPath = device_path.as_str().try_into()
                .map_err(|e: zbus::zvariant::Error| zbus::Error::Variant(e))?;
            let ap_paths: Vec<zbus::zvariant::OwnedObjectPath> = self.conn
                .call_method(
                    Some("org.freedesktop.NetworkManager"),
                    &path,
                    Some("org.freedesktop.NetworkManager.Device.Wireless"),
                    "GetAllAccessPoints",
                    &(),
                )
                .await?
                .body()
                .deserialize()?;
            
            for ap_path in ap_paths {
                if ap_path.as_str() == "/" {
                    continue;
                }
                
                let ssid_owned = self.get_ap_property(ap_path.as_str(), "Ssid").await;
                let ssid_bytes: Vec<u8> = ssid_owned
                    .ok()
                    .and_then(|ov| {
                        let v: zbus::zvariant::Value = ov.into();
                        if let zbus::zvariant::Value::Array(a) = v {
                            Some(a.iter().filter_map(|iv| {
                                u8::try_from(iv).ok()
                            }).collect())
                        } else {
                            None
                        }
                    })
                    .unwrap_or_default();
                
                let ssid = String::from_utf8_lossy(&ssid_bytes).to_string();
                
                if ssid.is_empty() {
                    continue;
                }
                
                let strength: u8 = self.get_ap_property(ap_path.as_str(), "Strength").await
                    .ok()
                    .and_then(|ov| u8::try_from(zbus::zvariant::Value::from(ov)).ok())
                    .unwrap_or(0);
                let flags: u32 = self.get_ap_property(ap_path.as_str(), "Flags").await
                    .ok()
                    .and_then(|ov| u32::try_from(zbus::zvariant::Value::from(ov)).ok())
                    .unwrap_or(0);
                let rsn_flags: u32 = self.get_ap_property(ap_path.as_str(), "RsnFlags").await
                    .ok()
                    .and_then(|ov| u32::try_from(zbus::zvariant::Value::from(ov)).ok())
                    .unwrap_or(0);
                let wpa_flags: u32 = self.get_ap_property(ap_path.as_str(), "WpaFlags").await
                    .ok()
                    .and_then(|ov| u32::try_from(zbus::zvariant::Value::from(ov)).ok())
                    .unwrap_or(0);
                
                let security = if rsn_flags & 0x100 != 0 {
                    SecurityType::WPA3
                } else if rsn_flags != 0 {
                    SecurityType::WPA2
                } else if wpa_flags != 0 {
                    SecurityType::WPA
                } else if flags != 0 {
                    SecurityType::WEP
                } else {
                    SecurityType::None
                };
                
                let is_connected = active_ssid.as_ref() == Some(&ssid);
                
                access_points.push(AccessPoint {
                    ssid,
                    signal_strength: strength,
                    security,
                    is_connected,
                    device_path: device_path.clone(),
                    path: ap_path.to_string(),
                });
            }
        }
        
        access_points.sort_by(|a, b| b.signal_strength.cmp(&a.signal_strength));
        
        let mut seen_ssids: std::collections::HashSet<String> = std::collections::HashSet::new();
        let mut unique_aps: Vec<AccessPoint> = Vec::new();
        
        for ap in access_points {
            if !seen_ssids.contains(&ap.ssid) {
                seen_ssids.insert(ap.ssid.clone());
                unique_aps.push(ap);
            } else if ap.is_connected {
                let existing = unique_aps.iter_mut().find(|x| x.ssid == ap.ssid);
                if let Some(existing) = existing {
                    existing.is_connected = true;
                }
            }
        }
        
        Ok(unique_aps)
    }
    
    async fn get_ap_property(&self, ap_path: &str, property: &str) -> zbus::Result<zbus::zvariant::OwnedValue> {
        let path: zbus::zvariant::ObjectPath = ap_path.try_into()
            .map_err(|e: zbus::zvariant::Error| zbus::Error::Variant(e))?;
        let reply = self.conn
            .call_method(
                Some("org.freedesktop.NetworkManager"),
                &path,
                Some("org.freedesktop.DBus.Properties"),
                "Get",
                &("org.freedesktop.NetworkManager.AccessPoint", property),
            )
            .await?
            .body()
            .deserialize::<zbus::zvariant::OwnedValue>()?;
        
        Ok(reply)
    }
    
    pub async fn get_active_ssid(&self) -> Option<String> {
        let active_paths = self.get_active_connection_paths().await;
        
        for path in active_paths {
            let path_obj = match zbus::zvariant::ObjectPath::try_from(path.as_str()) {
                Ok(p) => p,
                Err(_) => continue,
            };
            
            // Check connection type
            let type_reply = self.conn
                .call_method(
                    Some("org.freedesktop.NetworkManager"),
                    &path_obj,
                    Some("org.freedesktop.DBus.Properties"),
                    "Get",
                    &("org.freedesktop.NetworkManager.Connection.Active", "Type"),
                )
                .await;

            if let Ok(reply) = type_reply {
                if let Ok(type_val) = reply.body().deserialize::<zbus::zvariant::OwnedValue>() {
                    let val: zbus::zvariant::Value = type_val.into();
                    if let Ok(conn_type) = String::try_from(val) {
                        // Only allow WiFi or Ethernet
                        if conn_type != "802-11-wireless" && conn_type != "802-3-ethernet" {
                            continue;
                        }
                    }
                }
            }

            let id_reply = self.conn
                .call_method(
                    Some("org.freedesktop.NetworkManager"),
                    &path_obj,
                    Some("org.freedesktop.DBus.Properties"),
                    "Get",
                    &("org.freedesktop.NetworkManager.Connection.Active", "Id"),
                )
                .await;

            if let Ok(reply) = id_reply {
                if let Ok(id_val) = reply.body().deserialize::<zbus::zvariant::OwnedValue>() {
                    let val: zbus::zvariant::Value = id_val.into();
                    if let Ok(id) = String::try_from(val) {
                        // Additional blacklist for common virtual interface names
                        let lower_id = id.to_lowercase();
                        if lower_id.starts_with("docker") || 
                           lower_id.starts_with("br-") || 
                           lower_id.starts_with("veth") || 
                           lower_id.starts_with("lo") || 
                           lower_id.starts_with("virbr") {
                            continue;
                        }
                        return Some(id);
                    }
                }
            }
        }
        
        None
    }

    pub async fn has_saved_connection(&self, ssid: &str) -> bool {
        self.find_connection_by_ssid(ssid).await.is_some()
    }
    
    async fn find_connection_by_ssid(&self, ssid: &str) -> Option<String> {
        let connections_reply = self.conn
            .call_method(
                Some("org.freedesktop.NetworkManager"),
                "/org/freedesktop/NetworkManager/Settings",
                Some("org.freedesktop.NetworkManager.Settings"),
                "ListConnections",
                &(),
            )
            .await;

        let connections: Vec<zbus::zvariant::OwnedObjectPath> = match connections_reply {
            Ok(r) => r.body().deserialize().unwrap_or_default(),
            Err(e) => {
                log::error!("Failed to list connections: {}", e);
                return None;
            },
        };
        
        for conn_path in connections {
            if let Ok(settings) = self.get_connection_settings_raw(&conn_path).await {
                // Check for 802-11-wireless.ssid
                if let Some(wireless_map) = settings.get("802-11-wireless") {
                    if let Some(v) = wireless_map.get("ssid") {
                        let ssid_bytes = if let zbus::zvariant::Value::Array(a) = &**v {
                            a.iter().filter_map(|iv| u8::try_from(iv).ok()).collect::<Vec<u8>>()
                        } else {
                            Vec::new()
                        };
                        
                        if !ssid_bytes.is_empty() {
                            let stored_ssid = String::from_utf8_lossy(&ssid_bytes).to_string();
                            // Direct byte comparison or trimmed string comparison
                            if stored_ssid == ssid || stored_ssid.trim() == ssid.trim() || ssid_bytes == ssid.as_bytes() {
                                return Some(conn_path.to_string());
                            }
                        }
                    }
                }
                
                // Also check connection.id (SSID name often used here)
                if let Some(connection_map) = settings.get("connection") {
                    if let Some(id_owned) = connection_map.get("id") {
                        let val: &zbus::zvariant::Value = &**id_owned;
                        if let Ok(id) = <&str>::try_from(val) {
                            if id == ssid || id.trim() == ssid.trim() {
                                return Some(conn_path.to_string());
                            }
                        }
                    }
                }
            }
        }
        None
    }

    pub async fn connect_to_network(&self, ssid: &str, password: Option<&str>, device_path: &str) -> zbus::Result<()> {
        let dev_path: zbus::zvariant::ObjectPath = device_path.try_into()
            .map_err(|e: zbus::zvariant::Error| zbus::Error::Variant(e))?;

        if let Some(existing_path_str) = self.find_connection_by_ssid(ssid).await {
            let existing_path = zbus::zvariant::ObjectPath::try_from(existing_path_str.as_str()).unwrap();
            let specific_object = zbus::zvariant::ObjectPath::try_from("/").unwrap();
            
            self.conn.call_method(
                Some("org.freedesktop.NetworkManager"),
                "/org/freedesktop/NetworkManager",
                Some("org.freedesktop.NetworkManager"),
                "ActivateConnection",
                &(&existing_path, &dev_path, &specific_object),
            ).await?;
        } else {
            let mut connection: HashMap<&str, zbus::zvariant::Value> = HashMap::new();
            connection.insert("type", "802-11-wireless".into());
            connection.insert("id", ssid.into());
            connection.insert("uuid", zbus::zvariant::Value::Str(uuid::Uuid::new_v4().to_string().into()));
            connection.insert("autoconnect", true.into());
            
            let mut wireless: HashMap<&str, zbus::zvariant::Value> = HashMap::new();
            wireless.insert("ssid", ssid.as_bytes().into());
            wireless.insert("mode", "infrastructure".into());
            
            let mut config: HashMap<&str, HashMap<&str, zbus::zvariant::Value>> = HashMap::new();
            config.insert("connection", connection);
            config.insert("802-11-wireless", wireless);
            
            if let Some(pwd) = password {
                let mut wsec: HashMap<&str, zbus::zvariant::Value> = HashMap::new();
                wsec.insert("key-mgmt", "wpa-psk".into());
                wsec.insert("auth-alg", "open".into());
                wsec.insert("psk", pwd.into());
                config.insert("802-11-wireless-security", wsec);
            }
            
            let mut ipv4: HashMap<&str, zbus::zvariant::Value> = HashMap::new();
            ipv4.insert("method", "auto".into());
            config.insert("ipv4", ipv4);
            
            let mut ipv6: HashMap<&str, zbus::zvariant::Value> = HashMap::new();
            ipv6.insert("method", "ignore".into());
            config.insert("ipv6", ipv6);
            
            let specific_object = zbus::zvariant::ObjectPath::try_from("/").unwrap();
            self.conn
                .call_method(
                    Some("org.freedesktop.NetworkManager"),
                    "/org/freedesktop/NetworkManager",
                    Some("org.freedesktop.NetworkManager"),
                    "AddAndActivateConnection",
                    &(&config, &dev_path, &specific_object),
                )
                .await?;
        }
        
        let mut retries = 0;
        while retries < 30 {
            tokio::time::sleep(tokio::time::Duration::from_millis(500)).await;
            if let Some(current) = self.get_active_ssid().await {
                if current == ssid {
                    return Ok(());
                }
            }
            retries += 1;
        }
        Err(zbus::Error::Address("Connection timeout".to_string()))
    }

    pub async fn connect_hidden(&self, ssid: &str, password: Option<&str>, device_path: &str) -> zbus::Result<()> {
        let mut connection: HashMap<&str, zbus::zvariant::Value> = HashMap::new();
        connection.insert("type", "802-11-wireless".into());
        connection.insert("id", ssid.into());
        connection.insert("uuid", zbus::zvariant::Value::Str(uuid::Uuid::new_v4().to_string().into()));
        connection.insert("autoconnect", true.into());
        
        let mut wireless: HashMap<&str, zbus::zvariant::Value> = HashMap::new();
        wireless.insert("ssid", ssid.as_bytes().into());
        wireless.insert("mode", "infrastructure".into());
        wireless.insert("hidden", true.into());
        
        let mut config: HashMap<&str, HashMap<&str, zbus::zvariant::Value>> = HashMap::new();
        config.insert("connection", connection);
        config.insert("802-11-wireless", wireless);
        
        if let Some(pwd) = password {
            let mut wsec: HashMap<&str, zbus::zvariant::Value> = HashMap::new();
            wsec.insert("key-mgmt", "wpa-psk".into());
            wsec.insert("auth-alg", "open".into());
            wsec.insert("psk", pwd.into());
            config.insert("802-11-wireless-security", wsec);
        }
        
        let mut ipv4: HashMap<&str, zbus::zvariant::Value> = HashMap::new();
        ipv4.insert("method", "auto".into());
        config.insert("ipv4", ipv4);
        
        let mut ipv6: HashMap<&str, zbus::zvariant::Value> = HashMap::new();
        ipv6.insert("method", "ignore".into());
        config.insert("ipv6", ipv6);
        
        let dev_path: zbus::zvariant::ObjectPath = device_path.try_into()
            .map_err(|e: zbus::zvariant::Error| zbus::Error::Variant(e))?;
        
        let specific_object = zbus::zvariant::ObjectPath::try_from("/").unwrap();

        self.conn
            .call_method(
                Some("org.freedesktop.NetworkManager"),
                "/org/freedesktop/NetworkManager",
                Some("org.freedesktop.NetworkManager"),
                "AddAndActivateConnection",
                &(&config, &dev_path, &specific_object),
            )
            .await?;
        Ok(())
    }
    
    pub async fn disconnect_ap(&self, ssid: &str, _ap_path: &str) -> zbus::Result<()> {
        let active_paths = self.get_active_connection_paths().await;
        for path_str in active_paths {
            let path = match zbus::zvariant::ObjectPath::try_from(path_str.as_str()) {
                Ok(p) => p,
                Err(_) => continue,
            };

            let id_reply = self.conn
                .call_method(
                    Some("org.freedesktop.NetworkManager"),
                    &path,
                    Some("org.freedesktop.DBus.Properties"),
                    "Get",
                    &("org.freedesktop.NetworkManager.Connection.Active", "Id"),
                )
                .await;

            let id_val = match id_reply {
                Ok(r) => r.body().deserialize::<zbus::zvariant::OwnedValue>().ok(),
                Err(_) => None,
            };
            
            let id = id_val
                .and_then(|v| String::try_from(zbus::zvariant::Value::from(v)).ok())
                .unwrap_or_default();

            if id == ssid {
                self.conn
                    .call_method(
                        Some("org.freedesktop.NetworkManager"),
                        "/org/freedesktop/NetworkManager",
                        Some("org.freedesktop.NetworkManager"),
                        "DeactivateConnection",
                        &(path),
                    )
                    .await?;
                return Ok(());
            }
        }
        Ok(())
    }

    pub async fn forget_network(&self, path: &str) -> zbus::Result<()> {
        let path_obj: zbus::zvariant::ObjectPath = path.try_into()
            .map_err(|e: zbus::zvariant::Error| zbus::Error::Variant(e))?;
        self.conn
            .call_method(
                Some("org.freedesktop.NetworkManager"),
                &path_obj,
                Some("org.freedesktop.NetworkManager.Settings.Connection"),
                "Delete",
                &(),
            )
            .await?;
        Ok(())
    }

    pub async fn get_saved_networks(&self) -> zbus::Result<Vec<SavedNetwork>> {
        let connections_reply = self.conn
            .call_method(
                Some("org.freedesktop.NetworkManager"),
                "/org/freedesktop/NetworkManager/Settings",
                Some("org.freedesktop.NetworkManager.Settings"),
                "ListConnections",
                &(),
            )
            .await?;
        
        let connections: Vec<zbus::zvariant::OwnedObjectPath> = connections_reply.body().deserialize()?;
        let mut saved_networks = Vec::new();
        let active_connections = self.get_active_connection_paths().await;
        
        for conn_path in connections {
            if let Ok(settings) = self.get_connection_settings_raw(&conn_path).await {
                if let Some(connection_map) = settings.get("connection") {
                    let id = connection_map.get("id")
                        .and_then(|v| <&str>::try_from(&**v).ok())
                        .unwrap_or_default()
                        .to_string();
                    
                    let conn_type = connection_map.get("type")
                        .and_then(|v| <&str>::try_from(&**v).ok())
                        .unwrap_or_default();
                    
                    if conn_type == "802-11-wireless" {
                        let autoconnect = connection_map.get("autoconnect")
                            .and_then(|v| bool::try_from(&**v).ok())
                            .unwrap_or(true);
                        
                        let is_active = active_connections.contains(&conn_path.to_string());
                        
                        saved_networks.push(SavedNetwork {
                            ssid: id,
                            path: conn_path.to_string(),
                            autoconnect,
                            is_active,
                        });
                    }
                }
            }
        }
        saved_networks.sort_by(|a, b| b.is_active.cmp(&a.is_active).then_with(|| a.ssid.cmp(&b.ssid)));
        Ok(saved_networks)
    }

    async fn get_connection_settings_raw(&self, path: &zbus::zvariant::OwnedObjectPath) -> zbus::Result<HashMap<String, HashMap<String, zbus::zvariant::OwnedValue>>> {
        self.conn
            .call_method(
                Some("org.freedesktop.NetworkManager"),
                path,
                Some("org.freedesktop.NetworkManager.Settings.Connection"),
                "GetSettings",
                &(),
            )
            .await?
            .body()
            .deserialize()
    }

    async fn get_connection_settings_from_path(&self, path: &zbus::zvariant::ObjectPath<'_>) -> zbus::Result<HashMap<String, HashMap<String, zbus::zvariant::OwnedValue>>> {
        self.conn
            .call_method(
                Some("org.freedesktop.NetworkManager"),
                path,
                Some("org.freedesktop.NetworkManager.Settings.Connection"),
                "GetSettings",
                &(),
            )
            .await?
            .body()
            .deserialize()
    }
    
    async fn get_active_connection_paths(&self) -> Vec<String> {
        let reply = self.conn
            .call_method(
                Some("org.freedesktop.NetworkManager"),
                "/org/freedesktop/NetworkManager",
                Some("org.freedesktop.DBus.Properties"),
                "Get",
                &("org.freedesktop.NetworkManager", "ActiveConnections"),
            )
            .await;

        if let Ok(reply) = reply {
            if let Ok(val) = reply.body().deserialize::<zbus::zvariant::OwnedValue>() {
                let v: zbus::zvariant::Value = val.into();
                if let Ok(paths) = Vec::<zbus::zvariant::OwnedObjectPath>::try_from(v) {
                    return paths.into_iter().map(|p| p.to_string()).collect();
                }
            }
        }
        Vec::new()
    }

    pub async fn get_vpn_profiles(&self) -> zbus::Result<Vec<VpnProfile>> {
        let reply: Vec<zbus::zvariant::OwnedObjectPath> = self.conn
            .call_method(
                Some("org.freedesktop.NetworkManager"),
                "/org/freedesktop/NetworkManager/Settings",
                Some("org.freedesktop.NetworkManager.Settings"),
                "ListConnections",
                &(),
            )
            .await?
            .body()
            .deserialize()?;

        let active_paths = self.get_active_connection_paths().await;
        let mut profiles = Vec::new();

        for path in reply {
            let conn_props = match self.get_connection_settings_raw(&path).await {
                Ok(p) => p,
                Err(_) => continue,
            };

            if let Some(conn) = conn_props.get("connection") {
                if let Some(v) = conn.get("type") {
                    let val = zbus::zvariant::Value::try_from(v).unwrap();
                    if let Ok(conn_type) = <&str>::try_from(&val) {
                        let is_vpn = conn_type == "vpn" || 
                                    conn_type == "wireguard" || 
                                    conn_type == "tun" || 
                                    conn_type == "ppp";
                        
                        if is_vpn {
                            let name = conn.get("id")
                                .and_then(|v| {
                                    let val = zbus::zvariant::Value::try_from(v).ok()?;
                                    match val {
                                        zbus::zvariant::Value::Str(s) => Some(s.to_string()),
                                        _ => None,
                                    }
                                })
                                .unwrap_or_else(|| "Unknown VPN".to_string());

                            let mut is_active = false;
                            for active_path in &active_paths {
                                let path_obj = match zbus::zvariant::ObjectPath::try_from(active_path.as_str()) {
                                    Ok(p) => p,
                                    Err(_) => continue,
                                };
                                
                                let connection_path_reply: zbus::zvariant::OwnedValue = self.conn
                                    .call_method(
                                        Some("org.freedesktop.NetworkManager"),
                                        &path_obj,
                                        Some("org.freedesktop.DBus.Properties"),
                                        "Get",
                                        &("org.freedesktop.NetworkManager.Connection.Active", "Connection"),
                                    )
                                    .await?
                                    .body()
                                    .deserialize()?;
                                
                                let val: zbus::zvariant::Value = connection_path_reply.into();
                                let active_conn_path = zbus::zvariant::OwnedObjectPath::try_from(val).unwrap();
                                if active_conn_path.as_str() == path.as_str() {
                                    is_active = true;
                                    break;
                                }
                            }

                            profiles.push(VpnProfile {
                                name,
                                vpn_type: conn_type.to_string(),
                                path: path.to_string(),
                                is_active,
                                is_external: false,
                            });
                        }
                    }
                }
            }
        }

        // Detect External VPNs (Riseup, Tailscale, Mullvad)
        
        // Riseup VPN
        if std::path::Path::new("/usr/bin/riseup-vpn").exists() || std::path::Path::new("/usr/local/bin/riseup-vpn").exists() {
            // For Riseup, being "active" should mean the tunnel is up, not just the app is open
            let is_tunnel_up = std::process::Command::new("ip")
                .args(["addr", "show", "tun0"])
                .output()
                .map(|o| o.status.success())
                .unwrap_or(false);

            profiles.push(VpnProfile {
                name: "Riseup VPN".to_string(),
                vpn_type: if is_tunnel_up { "Secure Tunnel" } else { "App Open / Connecting" }.to_string(),
                path: "external:riseup".to_string(),
                is_active: is_tunnel_up,
                is_external: true,
            });
        }

        // Tailscale
        if std::path::Path::new("/usr/bin/tailscale").exists() || std::path::Path::new("/usr/local/bin/tailscale").exists() {
            let status = std::process::Command::new("tailscale")
                .arg("status")
                .output();
            
            let is_active = match status {
                Ok(o) => {
                    let s = String::from_utf8_lossy(&o.stdout);
                    !s.contains("Tailscale is stopped") && o.status.success()
                },
                Err(_) => false,
            };

            profiles.push(VpnProfile {
                name: "Tailscale".to_string(),
                vpn_type: "Mesh VPN".to_string(),
                path: "external:tailscale".to_string(),
                is_active,
                is_external: true,
            });
        }

        // Mullvad
        if std::path::Path::new("/usr/bin/mullvad").exists() || std::path::Path::new("/usr/local/bin/mullvad").exists() {
            let status = std::process::Command::new("mullvad")
                .arg("status")
                .output();
            
            let is_active = match status {
                Ok(o) => {
                    let s = String::from_utf8_lossy(&o.stdout);
                    s.to_lowercase().contains("connected")
                },
                Err(_) => false,
            };

            profiles.push(VpnProfile {
                name: "Mullvad VPN".to_string(),
                vpn_type: "WireGuard/OpenVPN".to_string(),
                path: "external:mullvad".to_string(),
                is_active,
                is_external: true,
            });
        }

        Ok(profiles)
    }

    pub async fn activate_vpn(&self, path: &str) -> zbus::Result<()> {
        if path.starts_with("external:") {
            let service = &path[9..];
            match service {
                "riseup" => {
                    // Use -n to avoid the splash/tray icon and -w to enable web-api
                    // No sudo here as we set the SUID bit on the helper
                    let _ = std::process::Command::new("sh")
                        .arg("-c")
                        .arg("nohup riseup-vpn -n -w --start-vpn on >/dev/null 2>&1 &")
                        .spawn();
                }
                "tailscale" => {
                    let _ = std::process::Command::new("tailscale").arg("up").status();
                }
                "mullvad" => {
                    let _ = std::process::Command::new("mullvad").arg("connect").status();
                }
                _ => {}
            }
            return Ok(());
        }

        let path_obj = zbus::zvariant::ObjectPath::try_from(path)
            .map_err(|e| zbus::Error::Variant(e))?;
        let device = zbus::zvariant::ObjectPath::try_from("/")
            .map_err(|e| zbus::Error::Variant(e))?;
        let specific = zbus::zvariant::ObjectPath::try_from("/")
            .map_err(|e| zbus::Error::Variant(e))?;
        
        self.conn
            .call_method(
                Some("org.freedesktop.NetworkManager"),
                "/org/freedesktop/NetworkManager",
                Some("org.freedesktop.NetworkManager"),
                "ActivateConnection",
                &(&path_obj, &device, &specific),
            )
            .await?;
        Ok(())
    }

    pub async fn deactivate_vpn(&self, path: &str) -> zbus::Result<()> {
        if path.starts_with("external:") {
            let service = &path[9..];
            match service {
                "riseup" => {
                    // Use pkexec for the root helper to ensure proper permission elevation via Polkit
                    let _ = std::process::Command::new("sh")
                        .arg("-c")
                        .arg("pkill riseup-vpn; sleep 1; pkexec /usr/sbin/bitmask-root firewall stop")
                        .status();
                }
                "tailscale" => {
                    let _ = std::process::Command::new("tailscale").arg("down").status();
                }
                "mullvad" => {
                    let _ = std::process::Command::new("mullvad").arg("disconnect").status();
                }
                _ => {}
            }
            return Ok(());
        }

        let active_paths = self.get_active_connection_paths().await;
        for active_path in active_paths {
            let path_obj = zbus::zvariant::ObjectPath::try_from(active_path.as_str())
                .map_err(|e| zbus::Error::Variant(e))?;
            
            let connection_path_reply: zbus::zvariant::OwnedValue = self.conn
                .call_method(
                    Some("org.freedesktop.NetworkManager"),
                    &path_obj,
                    Some("org.freedesktop.DBus.Properties"),
                    "Get",
                    &("org.freedesktop.NetworkManager.Connection.Active", "Connection"),
                )
                .await?
                .body()
                .deserialize()?;
            
            let val: zbus::zvariant::Value = connection_path_reply.into();
            let active_conn_path = zbus::zvariant::OwnedObjectPath::try_from(val).unwrap();
            if active_conn_path.as_str() == path {
                self.conn
                    .call_method(
                        Some("org.freedesktop.NetworkManager"),
                        "/org/freedesktop/NetworkManager",
                        Some("org.freedesktop.NetworkManager"),
                        "DeactivateConnection",
                        &(&path_obj),
                    )
                    .await?;
                return Ok(());
            }
        }
        Ok(())
    }

    pub async fn get_wired_devices(&self) -> zbus::Result<Vec<String>> {
        let devices: Vec<zbus::zvariant::OwnedObjectPath> = self.conn
            .call_method(
                Some("org.freedesktop.NetworkManager"),
                "/org/freedesktop/NetworkManager",
                Some("org.freedesktop.NetworkManager"),
                "GetDevices",
                &(),
            )
            .await?
            .body()
            .deserialize()?;
        
        let mut wired = Vec::new();
        
        for device_path in devices {
            let dtype_reply = self.conn
                .call_method(
                    Some("org.freedesktop.NetworkManager"),
                    &device_path,
                    Some("org.freedesktop.DBus.Properties"),
                    "Get",
                    &("org.freedesktop.NetworkManager.Device", "DeviceType"),
                )
                .await?
                .body()
                .deserialize::<zbus::zvariant::OwnedValue>()?;
            
            let device_type: u32 = match u32::try_from(zbus::zvariant::Value::from(dtype_reply)) {
                Ok(t) => t,
                Err(_) => 0,
            };
            
            if device_type == 1 {
                wired.push(device_path.to_string());
            }
        }
        
        Ok(wired)
    }
    
    async fn get_wired_device_property(&self, device_path: &str, property: &str) -> zbus::Result<zbus::zvariant::OwnedValue> {
        let path: zbus::zvariant::ObjectPath = device_path.try_into()
            .map_err(|e: zbus::zvariant::Error| zbus::Error::Variant(e))?;
        let reply = self.conn
            .call_method(
                Some("org.freedesktop.NetworkManager"),
                &path,
                Some("org.freedesktop.DBus.Properties"),
                "Get",
                &("org.freedesktop.NetworkManager.Device", property),
            )
            .await?
            .body()
            .deserialize::<zbus::zvariant::OwnedValue>()?;
        
        Ok(reply)
    }
    
    pub async fn get_wired_profiles(&self) -> zbus::Result<Vec<WiredProfile>> {
        let devices = self.get_wired_devices().await?;
        let mut profiles = Vec::new();
        
        for device_path in devices {
            let iface = self.get_wired_device_property(&device_path, "Interface").await
                .ok()
                .and_then(|v| String::try_from(zbus::zvariant::Value::from(v)).ok())
                .unwrap_or_else(|| "Unknown".to_string());
            
            let carrier = self.get_wired_device_property(&device_path, "Carrier").await
                .ok()
                .and_then(|v| bool::try_from(zbus::zvariant::Value::from(v)).ok())
                .unwrap_or(false);
            
            let speed = self.get_wired_device_property(&device_path, "Speed").await
                .ok()
                .and_then(|v| u32::try_from(zbus::zvariant::Value::from(v)).ok())
                .unwrap_or(0);
            
            let hw = self.get_wired_device_property(&device_path, "HwAddress").await
                .ok()
                .and_then(|v| String::try_from(zbus::zvariant::Value::from(v)).ok())
                .unwrap_or_default();
            
            let active_conn_path = self.get_wired_device_property(&device_path, "ActiveConnection").await
                .ok()
                .and_then(|v| {
                    let val = zbus::zvariant::Value::from(v);
                    zbus::zvariant::OwnedObjectPath::try_from(val).ok()
                });
            
            let mut name = iface.clone();
            let mut connection_path = String::new();
            let mut autoconnect = true;
            let mut is_active = false;
            let mut ip4_address = String::new();
            let mut gateway = String::new();
            let mut dns_servers = Vec::new();
            
            if let Some(ref active_path) = active_conn_path {
                if active_path.as_str() != "/" {
                    is_active = true;
                    
                    if let Ok(id_val) = self.conn
                        .call_method(
                            Some("org.freedesktop.NetworkManager"),
                            active_path,
                            Some("org.freedesktop.DBus.Properties"),
                            "Get",
                            &("org.freedesktop.NetworkManager.Connection.Active", "Id"),
                        )
                        .await
                    {
                        if let Ok(v) = id_val.body().deserialize::<zbus::zvariant::OwnedValue>() {
                            name = String::try_from(zbus::zvariant::Value::from(v)).unwrap_or(name);
                        }
                    }
                    
                    if let Ok(conn_val) = self.conn
                        .call_method(
                            Some("org.freedesktop.NetworkManager"),
                            active_path,
                            Some("org.freedesktop.DBus.Properties"),
                            "Get",
                            &("org.freedesktop.NetworkManager.Connection.Active", "Connection"),
                        )
                        .await
                    {
                        if let Ok(v) = conn_val.body().deserialize::<zbus::zvariant::OwnedValue>() {
                            let cp = zbus::zvariant::OwnedObjectPath::try_from(zbus::zvariant::Value::from(v))
                                .unwrap_or_else(|_| "/".try_into().unwrap());
                            connection_path = cp.to_string();
                        }
                    }
                    
                    if let Ok(ip4_val) = self.conn
                        .call_method(
                            Some("org.freedesktop.NetworkManager"),
                            active_path,
                            Some("org.freedesktop.DBus.Properties"),
                            "Get",
                            &("org.freedesktop.NetworkManager.Connection.Active", "Ip4Config"),
                        )
                        .await
                    {
                        if let Ok(v) = ip4_val.body().deserialize::<zbus::zvariant::OwnedValue>() {
                            let ip4_path = zbus::zvariant::OwnedObjectPath::try_from(zbus::zvariant::Value::from(v))
                                .unwrap_or_else(|_| "/".try_into().unwrap());
                            
                            if ip4_path.as_str() != "/" {
                                if let Ok(addr_val) = self.conn
                                    .call_method(
                                        Some("org.freedesktop.NetworkManager"),
                                        &ip4_path,
                                        Some("org.freedesktop.DBus.Properties"),
                                        "Get",
                                        &("org.freedesktop.NetworkManager.IP4Config", "AddressData"),
                                    )
                                    .await
                                {
                                    if let Ok(v) = addr_val.body().deserialize::<zbus::zvariant::OwnedValue>() {
                                        let val: zbus::zvariant::Value = v.into();
                                        if let zbus::zvariant::Value::Array(a) = val {
                                            for iv in a.iter() {
                                                let owned = zbus::zvariant::OwnedValue::try_from(iv)
                                                    .expect("Value should be convertible to OwnedValue");
                                                if let Ok(map) = HashMap::<String, zbus::zvariant::OwnedValue>::try_from(owned) {
                                                    if let Some(addr_v) = map.get("address") {
                                                        if let Ok(addr_str) = <&str>::try_from(&**addr_v) {
                                                            ip4_address = addr_str.to_string();
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                                
                                if let Ok(gw_val) = self.conn
                                    .call_method(
                                        Some("org.freedesktop.NetworkManager"),
                                        &ip4_path,
                                        Some("org.freedesktop.DBus.Properties"),
                                        "Get",
                                        &("org.freedesktop.NetworkManager.IP4Config", "Gateway"),
                                    )
                                    .await
                                {
                                    if let Ok(v) = gw_val.body().deserialize::<zbus::zvariant::OwnedValue>() {
                                        gateway = String::try_from(zbus::zvariant::Value::from(v)).unwrap_or_default();
                                    }
                                }
                                
                                if let Ok(dns_val) = self.conn
                                    .call_method(
                                        Some("org.freedesktop.NetworkManager"),
                                        &ip4_path,
                                        Some("org.freedesktop.DBus.Properties"),
                                        "Get",
                                        &("org.freedesktop.NetworkManager.IP4Config", "NameserverData"),
                                    )
                                    .await
                                {
                                    if let Ok(v) = dns_val.body().deserialize::<zbus::zvariant::OwnedValue>() {
                                        let dns_val: zbus::zvariant::Value = v.into();
                                        if let zbus::zvariant::Value::Array(a) = dns_val {
                                            for iv in a.iter() {
                                                let owned = zbus::zvariant::OwnedValue::try_from(iv)
                                                    .expect("Value should be convertible to OwnedValue");
                                                if let Ok(map) = HashMap::<String, zbus::zvariant::OwnedValue>::try_from(owned) {
                                                    if let Some(addr_v) = map.get("address") {
                                                        if let Ok(addr_str) = <&str>::try_from(&**addr_v) {
                                                            dns_servers.push(addr_str.to_string());
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            
            if connection_path.is_empty() {
                if let Ok(reply) = self.conn
                    .call_method(
                        Some("org.freedesktop.NetworkManager"),
                        "/org/freedesktop/NetworkManager/Settings",
                        Some("org.freedesktop.NetworkManager.Settings"),
                        "ListConnections",
                        &(),
                    )
                    .await
                {
                    if let Ok(paths) = reply.body().deserialize::<Vec<zbus::zvariant::OwnedObjectPath>>() {
                        for conn_path in paths {
                            if let Ok(props) = self.get_connection_settings_raw(&conn_path).await {
                                if let Some(conn) = props.get("connection") {
                                    let is_ethernet = conn.get("type")
                                        .and_then(|v| {
                                            let val = zbus::zvariant::Value::try_from(v).ok()?;
                                            <&str>::try_from(&val).map(|s| s == "802-3-ethernet").ok()
                                        })
                                        .unwrap_or(false);
                                    
                                    if is_ethernet {
                                        let matches_device = if let Some(conn_section) = props.get("connection") {
                                            conn_section.get("interface-name")
                                                .and_then(|v| {
                                                    let val = zbus::zvariant::Value::try_from(v).ok()?;
                                                    <&str>::try_from(&val).ok().map(|s: &str| s == iface.as_str())
                                                })
                                                .unwrap_or(false)
                                        } else {
                                            false
                                        };
                                        
                                        if matches_device {
                                            connection_path = conn_path.to_string();
                                            name = conn.get("id")
                                                .and_then(|v| {
                                                    let val = zbus::zvariant::Value::try_from(v).ok()?;
                                                    match val {
                                                        zbus::zvariant::Value::Str(s) => Some(s.to_string()),
                                                        _ => None,
                                                    }
                                                })
                                                .unwrap_or(name);
                                            autoconnect = conn.get("autoconnect")
                                                .and_then(|v| {
                                                    let val = zbus::zvariant::Value::try_from(v).ok()?;
                                                    bool::try_from(val).ok()
                                                })
                                                .unwrap_or(true);
                                            break;
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            } else {
                if let Ok(conn_path_obj) = zbus::zvariant::OwnedObjectPath::try_from(connection_path.as_str()) {
                    if let Ok(props) = self.get_connection_settings_raw(&conn_path_obj).await {
                        if let Some(conn) = props.get("connection") {
                            autoconnect = conn.get("autoconnect")
                                .and_then(|v| {
                                    let val = zbus::zvariant::Value::try_from(v).ok()?;
                                    bool::try_from(val).ok()
                                })
                                .unwrap_or(true);
                        }
                    }
                }
            }
            
            profiles.push(WiredProfile {
                name,
                device_name: iface,
                device_path,
                connection_path,
                is_active,
                has_carrier: carrier,
                speed,
                mac_address: hw,
                ip4_address,
                gateway,
                dns_servers,
                autoconnect,
            });
        }
        
        Ok(profiles)
    }
    
    pub async fn activate_wired_connection(&self, connection_path: &str, device_path: &str) -> zbus::Result<()> {
        let path_obj = zbus::zvariant::ObjectPath::try_from(connection_path)
            .map_err(|e| zbus::Error::Variant(e))?;
        let device = zbus::zvariant::ObjectPath::try_from(device_path)
            .map_err(|e| zbus::Error::Variant(e))?;
        let specific = zbus::zvariant::ObjectPath::try_from("/")
            .map_err(|e| zbus::Error::Variant(e))?;
        
        self.conn
            .call_method(
                Some("org.freedesktop.NetworkManager"),
                "/org/freedesktop/NetworkManager",
                Some("org.freedesktop.NetworkManager"),
                "ActivateConnection",
                &(&path_obj, &device, &specific),
            )
            .await?;
        Ok(())
    }
    
    pub async fn deactivate_wired_connection(&self, device_path: &str) -> zbus::Result<()> {
        let device_path_obj: zbus::zvariant::ObjectPath = device_path.try_into()
            .map_err(|e: zbus::zvariant::Error| zbus::Error::Variant(e))?;
        
        let active_conn = self.conn
            .call_method(
                Some("org.freedesktop.NetworkManager"),
                &device_path_obj,
                Some("org.freedesktop.DBus.Properties"),
                "Get",
                &("org.freedesktop.NetworkManager.Device", "ActiveConnection"),
            )
            .await?
            .body()
            .deserialize::<zbus::zvariant::OwnedValue>()?;
        
        let active_path = zbus::zvariant::OwnedObjectPath::try_from(zbus::zvariant::Value::from(active_conn))
            .unwrap_or_else(|_| "/".try_into().unwrap());
        
        if active_path.as_str() != "/" {
            self.conn
                .call_method(
                    Some("org.freedesktop.NetworkManager"),
                    "/org/freedesktop/NetworkManager",
                    Some("org.freedesktop.NetworkManager"),
                    "DeactivateConnection",
                    &(&active_path),
                )
                .await?;
        }
        Ok(())
    }
    
    pub async fn set_autoconnect(&self, path: &str, autoconnect: bool) -> zbus::Result<()> {
        let path_obj: zbus::zvariant::ObjectPath = path.try_into()
            .map_err(|e: zbus::zvariant::Error| zbus::Error::Variant(e))?;
        let current_settings = self.get_connection_settings_from_path(&path_obj).await?;
        let mut new_settings: HashMap<String, HashMap<String, zbus::zvariant::Value>> = HashMap::new();
        for (group_name, group_settings) in current_settings {
            let mut new_group: HashMap<String, zbus::zvariant::Value> = HashMap::new();
            for (key, value) in group_settings {
                new_group.insert(key, zbus::zvariant::Value::from(value));
            }
            new_settings.insert(group_name, new_group);
        }
        if let Some(conn_group) = new_settings.get_mut("connection") {
            conn_group.insert("autoconnect".to_string(), zbus::zvariant::Value::Bool(autoconnect));
        }
        self.conn
            .call_method(
                Some("org.freedesktop.NetworkManager"),
                &path_obj,
                Some("org.freedesktop.NetworkManager.Settings.Connection"),
                "Update",
                &(&new_settings),
            )
            .await?;
        Ok(())
    }
    
    pub async fn get_network_details(&self, ssid: &str) -> zbus::Result<NetworkDetails> {
        let mut details = NetworkDetails {
            ssid: ssid.to_string(),
            ..Default::default()
        };
        let active_paths = self.get_active_connection_paths().await;
        for path_str in active_paths {
            let path = match zbus::zvariant::ObjectPath::try_from(path_str.as_str()) {
                Ok(p) => p,
                Err(_) => continue,
            };
            let id_val_reply: zbus::zvariant::OwnedValue = self.conn
                .call_method(
                    Some("org.freedesktop.NetworkManager"),
                    &path,
                    Some("org.freedesktop.DBus.Properties"),
                    "Get",
                    &("org.freedesktop.NetworkManager.Connection.Active", "Id"),
                )
                .await?
                .body()
                .deserialize()?;
            
            let id = String::try_from(zbus::zvariant::Value::from(id_val_reply)).unwrap_or_default();
            
            if id == ssid {
                details.is_connected = true;
                let ip4_val_reply: zbus::zvariant::OwnedValue = self.conn
                    .call_method(
                        Some("org.freedesktop.NetworkManager"),
                        &path,
                        Some("org.freedesktop.DBus.Properties"),
                        "Get",
                        &("org.freedesktop.NetworkManager.Connection.Active", "Ip4Config"),
                    )
                    .await?
                    .body()
                    .deserialize()?;
                
                let ip4_path = zbus::zvariant::OwnedObjectPath::try_from(ip4_val_reply).unwrap_or_else(|_| "/".try_into().unwrap());
                
                if ip4_path.as_str() != "/" {
                    let addr_reply_val: zbus::zvariant::OwnedValue = self.conn
                        .call_method(
                            Some("org.freedesktop.NetworkManager"),
                            &ip4_path,
                            Some("org.freedesktop.DBus.Properties"),
                            "Get",
                            &("org.freedesktop.NetworkManager.IP4Config", "AddressData"),
                        )
                        .await?
                        .body()
                        .deserialize()?;
                    
                    let val: zbus::zvariant::Value = addr_reply_val.into();
                    if let zbus::zvariant::Value::Array(a) = val {
                        for iv in a.iter() {
                            let owned_iv = zbus::zvariant::OwnedValue::try_from(iv).expect("Value should be convertible to OwnedValue");
                            if let Ok(map) = HashMap::<String, zbus::zvariant::OwnedValue>::try_from(owned_iv) {
                                if let Some(address_v) = map.get("address") {
                                    if let Ok(addr_str) = <&str>::try_from(&**address_v) {
                                        details.ip4_address = addr_str.to_string();
                                    }
                                }
                            }
                        }
                    }
                    
                    let gateway_val_reply: zbus::zvariant::OwnedValue = self.conn
                        .call_method(
                            Some("org.freedesktop.NetworkManager"),
                            &ip4_path,
                            Some("org.freedesktop.DBus.Properties"),
                            "Get",
                            &("org.freedesktop.NetworkManager.IP4Config", "Gateway"),
                        )
                        .await?
                        .body()
                        .deserialize()?;
                    details.gateway = String::try_from(zbus::zvariant::Value::from(gateway_val_reply)).unwrap_or_default();
                    
                    let dns_reply_val: zbus::zvariant::OwnedValue = self.conn
                        .call_method(
                            Some("org.freedesktop.NetworkManager"),
                            &ip4_path,
                            Some("org.freedesktop.DBus.Properties"),
                            "Get",
                            &("org.freedesktop.NetworkManager.IP4Config", "NameserverData"),
                        )
                        .await?
                        .body()
                        .deserialize()?;
                    
                    let dns_val: zbus::zvariant::Value = dns_reply_val.into();
                    if let zbus::zvariant::Value::Array(a) = dns_val {
                        for iv in a.iter() {
                            let owned_iv = zbus::zvariant::OwnedValue::try_from(iv).expect("Value should be convertible to OwnedValue");
                            if let Ok(map) = HashMap::<String, zbus::zvariant::OwnedValue>::try_from(owned_iv) {
                                if let Some(address_v) = map.get("address") {
                                    if let Ok(addr_str) = <&str>::try_from(&**address_v) {
                                        details.ipv4_dns.push(addr_str.to_string());
                                    }
                                }
                            }
                        }
                    }
                }

                let ip6_val_reply: zbus::zvariant::OwnedValue = self.conn
                    .call_method(
                        Some("org.freedesktop.NetworkManager"),
                        &path,
                        Some("org.freedesktop.DBus.Properties"),
                        "Get",
                        &("org.freedesktop.NetworkManager.Connection.Active", "Ip6Config"),
                    )
                    .await?
                    .body()
                    .deserialize()?;
                
                let ip6_path = zbus::zvariant::OwnedObjectPath::try_from(ip6_val_reply).unwrap_or_else(|_| "/".try_into().unwrap());
                
                if ip6_path.as_str() != "/" {
                    let addr_reply_val: zbus::zvariant::OwnedValue = self.conn
                        .call_method(
                            Some("org.freedesktop.NetworkManager"),
                            &ip6_path,
                            Some("org.freedesktop.DBus.Properties"),
                            "Get",
                            &("org.freedesktop.NetworkManager.IP6Config", "AddressData"),
                        )
                        .await?
                        .body()
                        .deserialize()?;
                    
                    let val: zbus::zvariant::Value = addr_reply_val.into();
                    if let zbus::zvariant::Value::Array(a) = val {
                        for iv in a.iter() {
                            let owned_iv = zbus::zvariant::OwnedValue::try_from(iv).expect("Value should be convertible to OwnedValue");
                            if let Ok(map) = HashMap::<String, zbus::zvariant::OwnedValue>::try_from(owned_iv) {
                                if let Some(address_v) = map.get("address") {
                                    if let Ok(addr_str) = <&str>::try_from(&**address_v) {
                                        details.ip6_address = addr_str.to_string();
                                    }
                                }
                            }
                        }
                    }

                    let dns6_reply_val: zbus::zvariant::OwnedValue = self.conn
                        .call_method(
                            Some("org.freedesktop.NetworkManager"),
                            &ip6_path,
                            Some("org.freedesktop.DBus.Properties"),
                            "Get",
                            &("org.freedesktop.NetworkManager.IP6Config", "Nameservers"),
                        )
                        .await?
                        .body()
                        .deserialize()?;
                    
                    let dns6_val: zbus::zvariant::Value = dns6_reply_val.into();
                    if let zbus::zvariant::Value::Array(a) = dns6_val {
                        for iv in a.iter() {
                            if let zbus::zvariant::Value::Array(ba) = iv {
                                let bytes: Vec<u8> = ba.iter().filter_map(|bv| u8::try_from(bv).ok()).collect();
                                if bytes.len() == 16 {
                                    let octets: [u8; 16] = bytes.try_into().unwrap();
                                    let addr = std::net::Ipv6Addr::from(octets);
                                    details.ipv6_dns.push(addr.to_string());
                                }
                            }
                        }
                    }
                }
                
                let dev_reply_val: zbus::zvariant::OwnedValue = self.conn
                    .call_method(
                        Some("org.freedesktop.NetworkManager"),
                        &path,
                        Some("org.freedesktop.DBus.Properties"),
                        "Get",
                        &("org.freedesktop.NetworkManager.Connection.Active", "Devices"),
                    )
                    .await?
                    .body()
                    .deserialize()?;
                
                let dev_val: zbus::zvariant::Value = dev_reply_val.into();
                if let zbus::zvariant::Value::Array(a) = dev_val {
                    for iv in a.iter() {
                        let owned_iv = zbus::zvariant::OwnedValue::try_from(iv).expect("Value should be convertible to OwnedValue");
                        if let Ok(device_path) = zbus::zvariant::OwnedObjectPath::try_from(owned_iv) {
                             let hw_val_reply: zbus::zvariant::OwnedValue = self.conn
                                .call_method(
                                    Some("org.freedesktop.NetworkManager"),
                                    &device_path,
                                    Some("org.freedesktop.DBus.Properties"),
                                    "Get",
                                    &("org.freedesktop.NetworkManager.Device", "HwAddress"),
                                )
                                .await?
                                .body()
                                .deserialize()?;
                             details.mac_address = String::try_from(zbus::zvariant::Value::from(hw_val_reply)).unwrap_or_default();
                             
                             // Get connection speed
                             let speed_reply: zbus::zvariant::OwnedValue = self.conn
                                .call_method(
                                    Some("org.freedesktop.NetworkManager"),
                                    &device_path,
                                    Some("org.freedesktop.DBus.Properties"),
                                    "Get",
                                    &("org.freedesktop.NetworkManager.Device.Wireless", "Bitrate"),
                                )
                                .await?
                                .body()
                                .deserialize()?;
                             
                             if let Ok(bitrate_val) = u32::try_from(zbus::zvariant::Value::from(speed_reply)) {
                                 if bitrate_val > 0 {
                                     details.connection_speed = format!("{} Mb/s", bitrate_val / 1000);
                                 }
                             }
                             
                             break;

                        }
                    }
                }
                break;
            }
        }
        Ok(details)
    }
}
