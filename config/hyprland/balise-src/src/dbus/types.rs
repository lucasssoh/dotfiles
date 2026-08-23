//! Public WiFi data types, adapted from
//! orbit-vendor/src/dbus/network_manager.rs:4-42. `serde` derives dropped
//! -- nothing serializes these any more (that was only for Orbit's
//! `waybar-status`, which Balise doesn't have).

#[derive(Debug, Clone, PartialEq)]
pub enum SecurityType {
    None,
    Wep,
    Wpa,
    Wpa2,
    Wpa3,
}

impl SecurityType {
    /// Classification adapted from network_manager.rs:275-285 (NM's
    /// AccessPoint Flags/WpaFlags/RsnFlags bitmasks) -- with one bit
    /// corrected. Orbit's version checks `rsn_flags & 0x100`, believing
    /// that to be NM_802_11_AP_SEC_KEY_MGMT_SAE (WPA3); it's actually
    /// NM_802_11_AP_SEC_KEY_MGMT_PSK (WPA2-PSK), present on nearly every
    /// password-protected AP -- confirmed live via `busctl` against real
    /// access points (a WPA2-PSK Freebox AP read RsnFlags=392=0x188,
    /// which includes 0x100; a WPA3-SAE AP read RsnFlags=1160=0x488,
    /// which does NOT include 0x100 but does include 0x400). The real SAE
    /// bit is NM_802_11_AP_SEC_KEY_MGMT_SAE = 0x400.
    pub fn from_flags(flags: u32, wpa_flags: u32, rsn_flags: u32) -> Self {
        if rsn_flags & 0x400 != 0 {
            Self::Wpa3
        } else if rsn_flags != 0 {
            Self::Wpa2
        } else if wpa_flags != 0 {
            Self::Wpa
        } else if flags != 0 {
            // NM_802_11_AP_FLAGS_PRIVACY
            Self::Wep
        } else {
            Self::None
        }
    }

    pub fn label(&self) -> &'static str {
        match self {
            Self::None => "Open",
            Self::Wep => "WEP",
            Self::Wpa => "WPA",
            Self::Wpa2 => "WPA2",
            Self::Wpa3 => "WPA3",
        }
    }

    pub fn needs_password(&self) -> bool {
        !matches!(self, Self::None)
    }
}

#[derive(Debug, Clone)]
pub struct AccessPoint {
    pub ssid: String,
    pub signal: u8,
    pub security: SecurityType,
    pub is_connected: bool,
    /// Whether a saved profile already exists for this SSID -- computed
    /// up front in `access_points()` from one `wifi_profiles()` call,
    /// rather than Orbit's `has_saved_connection(ssid)` re-querying
    /// NetworkManager on every row click (see the project plan's §6.4).
    pub is_saved: bool,
    pub device_path: String,
    pub ap_path: String,
}

#[derive(Debug, Clone)]
pub struct SavedNetwork {
    /// The real 802-11-wireless.ssid, not connection.id (see the project
    /// plan's §6.2 -- Orbit's get_active_ssid conflates the two).
    pub ssid: String,
    /// connection.id, kept separately for display when a profile has been
    /// renamed away from its SSID.
    pub id: String,
    pub settings_path: String,
    pub autoconnect: bool,
    /// Correctly computed against Connection.Active.Connection (see the
    /// project plan's §6.1 -- Orbit's own get_saved_networks compares the
    /// wrong path namespace and is always false).
    pub is_active: bool,
}

/// Phase 2 (Ethernet). Adapted from network_manager.rs:22-72's identically
/// named struct.
#[derive(Debug, Clone, Default)]
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
