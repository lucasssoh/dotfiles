//! WiFi sharing: the `WIFI:` URI a phone's camera understands, and the QR
//! matrix it gets drawn as.
//!
//! Both halves live here, away from the D-Bus layer, because neither is
//! about NetworkManager: `network_manager.rs` only reads the stored
//! profile (its SSID, its security kind, its secret) and hands the pieces
//! over. The URI format is the de-facto one every phone camera
//! implements -- ZXing's `WIFI:` scheme, adopted by Android's own QR
//! joiner and by iOS since 11 -- not an IETF or Wi-Fi Alliance standard,
//! which is why the escaping rules below are spelled out rather than
//! deferred to a crate.
//!
//! The matrix is produced HERE, daemon-side, rather than by handing the
//! URI to whichever UI is going to draw it. That is deliberate: the URI
//! contains the network's passphrase in plain text, and this way it never
//! leaves the thread that built it -- neither the GTK widget tree nor the
//! QML frontend (which would have received it over the socket) ever holds
//! it. They get black-and-white bits.

use serde::Serialize;

use crate::dbus::SecurityType;

/// A rendered QR code, as a square grid of modules: one string of '0'
/// (light) / '1' (dark) per row, `size` characters each.
///
/// Strings rather than `Vec<Vec<bool>>` because this crosses the IPC
/// socket as JSON (see `ServerPush::WifiShare`) and 41 rows of `"0101…"`
/// is a fraction of the bytes -- and of the parsing -- that 41 nested
/// arrays of `true`/`false` would be on the QML side.
///
/// No quiet zone: the 4-module light border every QR needs is a drawing
/// concern, added by each renderer (see `to_ascii` here, the DrawingArea
/// in ui/detail.rs, the Canvas in BaliseDetailPage.qml) rather than baked
/// into the data.
#[derive(Debug, Clone, Default, Serialize)]
pub struct QrMatrix {
    pub size: u32,
    pub rows: Vec<String>,
}

impl QrMatrix {
    /// A matrix that carries no code -- what the error paths push, so the
    /// wire shape stays the same whether or not there was something to
    /// share.
    pub fn is_empty(&self) -> bool {
        self.size == 0 || self.rows.is_empty()
    }

    /// Out-of-range coordinates read as light, so a renderer can walk the
    /// quiet zone with the same call it uses for the code itself.
    pub fn is_dark(&self, x: usize, y: usize) -> bool {
        self.rows.get(y).and_then(|row| row.as_bytes().get(x)).is_some_and(|c| *c == b'1')
    }

    /// Terminal rendering for the `balise wifi-share` probe, two module
    /// rows per text row via the half-block glyphs.
    ///
    /// Drawn the way `nmcli device wifi show-password` draws its own:
    /// white foreground on black background, with the LIGHT modules as
    /// the glyphs. That is not an inverted code -- light stays light --
    /// it just avoids depending on the terminal's own background being
    /// white, which is what a naive "print dark modules as blocks" does.
    pub fn to_ascii(&self) -> String {
        const QUIET: usize = 4;
        if self.is_empty() {
            return String::new();
        }

        let span = self.size as usize + QUIET * 2;
        let mut out = String::new();
        // Two module rows per line, so the code comes out roughly square
        // in a terminal cell grid (cells are about twice as tall as wide).
        for pair in (0..span).step_by(2) {
            out.push_str("\x1b[37;40m  ");
            for x in 0..span {
                let upper = self.light(x, pair, QUIET);
                let lower = self.light(x, pair + 1, QUIET);
                out.push(match (upper, lower) {
                    (true, true) => '█',
                    (true, false) => '▀',
                    (false, true) => '▄',
                    (false, false) => ' ',
                });
            }
            out.push_str("  \x1b[0m\n");
        }
        out
    }

    /// Whether the module at a quiet-zone-offset coordinate is light.
    /// Anything outside the code -- the border, and the half-row a code
    /// with an odd span leaves dangling -- is light.
    fn light(&self, x: usize, y: usize, quiet: usize) -> bool {
        let span = self.size as usize + quiet * 2;
        if x < quiet || y < quiet || x >= span - quiet || y >= span - quiet {
            return true;
        }
        !self.is_dark(x - quiet, y - quiet)
    }
}

/// Encodes `text` at the default error-correction level (M, 15%) -- the
/// same level every phone-facing QR generator defaults to. `None` only
/// when the text doesn't fit in the largest QR version at all, which a
/// passphrase-length URI cannot reach.
pub fn encode(text: &str) -> Option<QrMatrix> {
    let code = qrcode::QrCode::new(text.as_bytes()).ok()?;
    let size = code.width();
    let colors = code.to_colors();

    let rows = colors
        .chunks(size)
        .map(|row| row.iter().map(|c| c.select('1', '0')).collect::<String>())
        .collect();

    Some(QrMatrix { size: size as u32, rows })
}

/// The `T:` token for a security kind, or `None` for the kinds that
/// cannot be expressed in this format at all.
///
/// 802.1X is the whole of that second category: the `WIFI:` scheme has no
/// way to carry a username, an EAP method or a CA certificate, iOS
/// ignores the extension fields some generators add for it, and Android
/// only provisions enterprise networks through DPP or a configuration
/// profile. An eduroam QR code would scan and then fail to join, which is
/// worse than not offering one -- hence `None`, and the caller refusing
/// up front.
///
/// WPA3 gets `SAE` rather than being folded into `WPA`: a phone told
/// `WPA` builds a WPA2-PSK profile, which associates with a
/// transition-mode AP but not with a WPA3-only one. `SAE` needs Android
/// 10 / iOS 15, both of which predate any AP that would be WPA3-only.
fn auth_token(security: &SecurityType) -> Option<&'static str> {
    match security {
        SecurityType::None => Some("nopass"),
        SecurityType::Wep => Some("WEP"),
        SecurityType::Wpa | SecurityType::Wpa2 => Some("WPA"),
        SecurityType::Wpa3 => Some("SAE"),
        SecurityType::Enterprise | SecurityType::Wpa3Enterprise => None,
    }
}

/// Whether a network of this kind can be shared as a QR code at all --
/// the gate the UI puts its "Share" action behind, so the button simply
/// isn't there for eduroam rather than being there and failing.
pub fn is_shareable(security: &SecurityType) -> bool {
    auth_token(security).is_some()
}

/// `\`, `;`, `,`, `:` and `"` are the format's own delimiters and have to
/// be backslash-escaped inside a value -- a passphrase containing a
/// semicolon is otherwise read as the end of the field.
fn escape(value: &str) -> String {
    let mut out = String::with_capacity(value.len());
    for c in value.chars() {
        if matches!(c, '\\' | ';' | ',' | ':' | '"') {
            out.push('\\');
        }
        out.push(c);
    }
    out
}

/// A value that is entirely hexadecimal digits has to be double-quoted,
/// or a reader takes it for a hex-encoded byte string and joins a network
/// named after its own decoded bytes. Applies to the SSID and the
/// passphrase alike; the quotes go around the already-escaped text.
fn field(value: &str) -> String {
    let escaped = escape(value);
    if !value.is_empty() && value.chars().all(|c| c.is_ascii_hexdigit()) {
        format!("\"{}\"", escaped)
    } else {
        escaped
    }
}

/// Builds the URI a camera app turns into a "join this network?" prompt.
///
/// `secret` is ignored for an open network (there is nothing to carry)
/// and is the passphrase or the WEP key otherwise. `hidden` mirrors the
/// profile's own `802-11-wireless.hidden`: without it a phone won't find
/// a non-broadcasting network no matter how right the rest is.
///
/// Returns `None` for a security kind that has no representation here --
/// see `auth_token`.
pub fn wifi_uri(ssid: &str, security: &SecurityType, secret: &str, hidden: bool) -> Option<String> {
    let token = auth_token(security)?;

    let mut uri = format!("WIFI:T:{};S:{};", token, field(ssid));
    if security.needs_password() {
        uri.push_str(&format!("P:{};", field(secret)));
    }
    if hidden {
        uri.push_str("H:true;");
    }
    // The trailing empty field is part of the format: the URI ends on a
    // doubled separator, one closing the last field and one closing the
    // record.
    uri.push(';');

    Some(uri)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn personal_network_carries_its_passphrase() {
        let uri = wifi_uri("Freebox-C76C28", &SecurityType::Wpa2, "hunter2", false).unwrap();
        assert_eq!(uri, "WIFI:T:WPA;S:Freebox-C76C28;P:hunter2;;");
    }

    #[test]
    fn open_network_carries_no_password_field() {
        let uri = wifi_uri("CafeWifi", &SecurityType::None, "", false).unwrap();
        assert_eq!(uri, "WIFI:T:nopass;S:CafeWifi;;");
    }

    #[test]
    fn wpa3_is_sae_not_wpa() {
        // A phone handed `WPA` builds a WPA2-PSK profile, which a
        // WPA3-only AP won't associate with -- see auth_token.
        let uri = wifi_uri("Maison", &SecurityType::Wpa3, "hunter2", false).unwrap();
        assert!(uri.starts_with("WIFI:T:SAE;"), "got {uri}");
    }

    #[test]
    fn enterprise_has_no_representation() {
        assert!(wifi_uri("eduroam", &SecurityType::Enterprise, "hunter2", false).is_none());
        assert!(wifi_uri("eduroam", &SecurityType::Wpa3Enterprise, "hunter2", false).is_none());
        assert!(!is_shareable(&SecurityType::Enterprise));
        assert!(is_shareable(&SecurityType::Wpa2));
    }

    #[test]
    fn hidden_network_says_so() {
        let uri = wifi_uri("Discret", &SecurityType::Wpa2, "hunter2", true).unwrap();
        assert_eq!(uri, "WIFI:T:WPA;S:Discret;P:hunter2;H:true;;");
    }

    #[test]
    fn delimiters_inside_a_value_are_escaped() {
        // Without this the reader stops the passphrase at the semicolon
        // and joins with half a key.
        let uri = wifi_uri("Chez;Moi", &SecurityType::Wpa2, r#"a:b;c,d"e\f"#, false).unwrap();
        assert_eq!(uri, r#"WIFI:T:WPA;S:Chez\;Moi;P:a\:b\;c\,d\"e\\f;;"#);
    }

    #[test]
    fn all_hex_values_are_quoted() {
        // "abcdef" unquoted is read as three decoded bytes, not a name.
        let uri = wifi_uri("abcdef", &SecurityType::Wpa2, "0123456789", false).unwrap();
        assert_eq!(uri, "WIFI:T:WPA;S:\"abcdef\";P:\"0123456789\";;");
        // Only when it is ENTIRELY hex digits.
        let uri = wifi_uri("abcdefg", &SecurityType::None, "", false).unwrap();
        assert_eq!(uri, "WIFI:T:nopass;S:abcdefg;;");
    }

    #[test]
    fn encoding_produces_a_square_grid_of_the_declared_size() {
        let qr = encode("WIFI:T:WPA;S:Freebox-C76C28;P:hunter2;;").unwrap();
        assert!(qr.size >= 21, "a QR is at least version 1 (21x21), got {}", qr.size);
        assert_eq!(qr.rows.len(), qr.size as usize);
        assert!(qr.rows.iter().all(|r| r.chars().count() == qr.size as usize));
        assert!(qr.rows.iter().all(|r| r.chars().all(|c| c == '0' || c == '1')));
        // The finder pattern's own corner: dark, in every QR ever made.
        assert!(qr.is_dark(0, 0));
        assert!(!qr.is_empty());
    }

    #[test]
    fn out_of_range_modules_read_as_light() {
        let qr = encode("WIFI:T:nopass;S:x;;").unwrap();
        let n = qr.size as usize;
        assert!(!qr.is_dark(n, 0));
        assert!(!qr.is_dark(0, n));
        assert!(QrMatrix::default().is_empty());
    }
}
