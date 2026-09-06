//! Public WiFi data types, adapted from
//! orbit-vendor/src/dbus/network_manager.rs:4-42. `serde` derives were
//! dropped when this was ported (nothing serialized these for Orbit's
//! own purposes) -- back now (`Serialize` only, see ipc.rs's own header
//! for why not `Deserialize` too) for `ServerPush::WifiList`/
//! `WiredList`, the QML frontend's WiFi/Ethernet section lists.

use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, PartialEq, Default, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum SecurityType {
    #[default]
    None,
    Wep,
    Wpa,
    Wpa2,
    Wpa3,
    /// WPA/WPA2-Enterprise -- 802.1X, so a username AND a password (plus
    /// an EAP method), not a shared key. This is what eduroam and most
    /// campus/corporate networks are.
    Enterprise,
    /// WPA3-Enterprise (Suite-B-192). Same credentials as `Enterprise`,
    /// different `key-mgmt` when a profile is written.
    Wpa3Enterprise,
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
    ///
    /// The 802.1X (enterprise) and OWE bits are checked FIRST, and ahead
    /// of SAE/PSK, because they change what the user has to type rather
    /// than just which `key-mgmt` string gets written: enterprise wants a
    /// username + password, OWE ("Enhanced Open") wants nothing at all.
    /// Both used to fall through to `Wpa2`, which asked for a passphrase
    /// that could never work. Bit values from NM's own
    /// `NM80211ApSecurityFlags`.
    pub fn from_flags(flags: u32, wpa_flags: u32, rsn_flags: u32) -> Self {
        const KEY_MGMT_802_1X: u32 = 0x200;
        const KEY_MGMT_SAE: u32 = 0x400;
        const KEY_MGMT_OWE: u32 = 0x800;
        const KEY_MGMT_EAP_SUITE_B_192: u32 = 0x2000;

        if rsn_flags & KEY_MGMT_EAP_SUITE_B_192 != 0 {
            Self::Wpa3Enterprise
        } else if (rsn_flags | wpa_flags) & KEY_MGMT_802_1X != 0 {
            Self::Enterprise
        } else if rsn_flags & KEY_MGMT_SAE != 0 {
            Self::Wpa3
        } else if rsn_flags & KEY_MGMT_OWE != 0 {
            // Opportunistic Wireless Encryption: encrypted, but with no
            // credential of any kind -- "open" as far as the user is
            // concerned, and NM joins it with no security group at all.
            Self::None
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
            Self::Enterprise => "WPA2-Enterprise",
            Self::Wpa3Enterprise => "WPA3-Enterprise",
        }
    }

    pub fn needs_password(&self) -> bool {
        !matches!(self, Self::None)
    }

    /// 802.1X: a username (`identity`) and an EAP method are needed on top
    /// of the password, and the profile gets an `802-1x` settings group.
    pub fn is_enterprise(&self) -> bool {
        matches!(self, Self::Enterprise | Self::Wpa3Enterprise)
    }

    /// Inverse of the `Serialize` derive above -- parses the same
    /// snake_case token back, for `ClientCommand::WifiConnect`'s own
    /// `security` field (the frontend echoes back the string it was given
    /// in the access-point list).
    ///
    /// A plain function with a fallback rather than a `Deserialize`
    /// derive: an unrecognised token must NOT fail the whole command, and
    /// WPA2-PSK is both the overwhelmingly common case and exactly what
    /// the code assumed unconditionally before this existed.
    pub fn from_wire(s: &str) -> Self {
        match s {
            "none" => Self::None,
            "wep" => Self::Wep,
            "wpa" => Self::Wpa,
            "wpa3" => Self::Wpa3,
            "enterprise" => Self::Enterprise,
            "wpa3_enterprise" => Self::Wpa3Enterprise,
            _ => Self::Wpa2,
        }
    }
}

/// Everything the user can type to join a network, in one struct rather
/// than the bare `Option<&str>` password `connect()` took before -- an
/// enterprise network (eduroam and friends) needs a username and an EAP
/// method alongside the password, and a WPA3 one needs the same passphrase
/// written under a different `key-mgmt`.
///
/// `Deserialize` as well as `Serialize` (unlike everything else in this
/// file): this one travels client -> daemon, inside
/// `ClientCommand::WifiConnect`. Every field is optional at the wire level
/// and empty-by-default, so `{"cmd":"wifi_connect","ssid":"x"}` still
/// means "join with no credentials" exactly as it did before.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct WifiCredentials {
    /// PSK/passphrase for personal networks, user password for enterprise.
    #[serde(default)]
    pub password: String,
    /// 802.1X username. Enterprise only, ignored otherwise.
    #[serde(default)]
    pub identity: String,
    /// 802.1X outer identity, e.g. `anonymous@univ.fr` -- optional even
    /// for enterprise; omitted from the profile when empty.
    #[serde(default)]
    pub anonymous_identity: String,
    /// NM's `802-1x.eap`, one of "peap" / "ttls" / "pwd". Empty falls back
    /// to "peap", which is what eduroam deployments overwhelmingly use.
    #[serde(default)]
    pub eap_method: String,
    /// NM's `802-1x.phase2-auth`, one of "mschapv2" / "pap" / "gtc".
    /// Empty falls back to "mschapv2". Not written for EAP-PWD, which has
    /// no inner phase.
    #[serde(default)]
    pub phase2_auth: String,
}

impl WifiCredentials {
    /// Whether the user actually typed something. A credentials object
    /// full of empty strings is treated exactly like none at all, so an
    /// accidental empty submit can't overwrite a working saved profile's
    /// secrets with blanks.
    pub fn is_empty(&self) -> bool {
        self.password.is_empty() && self.identity.is_empty()
    }
}

// Default is used to synthesise an entry for a saved network that the
// last scan didn't see (out of range), so its detail page can still be
// opened from the saved-networks overlay -- see app/mod.rs.
#[derive(Debug, Clone, Default, Serialize)]
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

#[derive(Debug, Clone, Serialize)]
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
#[derive(Debug, Clone, Default, Serialize)]
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

/// Everything the WiFi detail page shows beyond what a scanned
/// `AccessPoint` already carries. Split in two halves, because they have
/// different availability: the saved-profile half (`settings_path`,
/// `autoconnect`) exists for any network with a stored profile even when
/// it's down, while the live half (addresses, MAC, speed) only exists
/// while this SSID is the *active* connection. Everything is
/// `Default`-empty otherwise, and the UI simply omits empty rows.
/// `Serialize` added for the QML frontend's own detail page (third
/// slice, see the project plan) -- `ServerPush::WifiDetail`.
#[derive(Debug, Clone, Default, Serialize)]
pub struct WifiDetails {
    pub ssid: String,
    pub is_connected: bool,
    pub ip4_address: String,
    pub ip6_address: String,
    pub gateway: String,
    pub dns_servers: Vec<String>,
    pub mac_address: String,
    /// Human-readable ("650 Mb/s"), empty when not connected -- the raw
    /// NM `Bitrate` is in kb/s, converted at read time.
    pub speed: String,
    /// Settings/N path of the stored profile, empty when the network has
    /// never been saved. Non-empty is what enables Forget/autoconnect.
    pub settings_path: String,
    pub autoconnect: bool,
    /// The stored profile's own security kind, read back from its
    /// `key-mgmt`. `None` when the network has no profile -- which is a
    /// different thing from `Some(SecurityType::None)` (a profile for an
    /// open network), hence the Option rather than the enum's own default.
    ///
    /// Exists so the credential form can be offered for a SAVED network
    /// that the last scan didn't see: `AccessPoint.security` is the
    /// natural source, but an out-of-range network has no AccessPoint at
    /// all, and "change the password on the eduroam profile I'm not
    /// currently near" is exactly when you'd want to.
    pub security: Option<SecurityType>,
}
