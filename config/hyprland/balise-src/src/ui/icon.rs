//! Phosphor icon glyphs -- the established icon language for this whole
//! ecosystem (see quickshell/bar/theme/Fonts.qml's `iconPhosphor` and its
//! header comment: MIT-licensed, several distinct weights, installed to
//! ~/.local/share/fonts by install.sh's "PHOSPHOR ICONS" section). Balise
//! previously used GTK's system icon-theme lookups
//! (icon_name("view-refresh-symbolic") etc.), which don't draw from the
//! same font and read as a mismatched icon language next to the rest of
//! the desktop. These are real Unicode codepoints from the Regular
//! weight (font-family "Phosphor"), taken from the upstream
//! phosphor-icons/core repo's codepoint metadata (src/icons.ts) rather
//! than guessed.
//!
//! CSS side: `.balise-icon` sets `font-family: "Phosphor"` (see
//! style.css) on whatever Label carries one of these glyphs.

pub const ARROWS_CLOCKWISE: &str = "\u{E094}"; // Scan/refresh
pub const EYE_SLASH: &str = "\u{E224}"; // Hidden network
pub const CLOCK_COUNTER_CLOCKWISE: &str = "\u{E1A0}"; // Saved networks (history)
pub const LOCK_SIMPLE: &str = "\u{E308}"; // Secure-network indicator
pub const X: &str = "\u{E4F6}"; // Close buttons
pub const WARNING_CIRCLE: &str = "\u{E4E2}"; // Error toast

pub const BLUETOOTH: &str = "\u{E0DA}"; // Generic device-row icon (Phase 3), also the Bluetooth home tile
pub const BLUETOOTH_CONNECTED: &str = "\u{E0DC}";
#[allow(dead_code)]
pub const BLUETOOTH_SLASH: &str = "\u{E0DE}";

pub const PLUGS_CONNECTED: &str = "\u{EB5A}"; // Ethernet row/tile, active/carrier
pub const PLUGS: &str = "\u{EB56}"; // Ethernet row/tile, no cable (Phase 2)

// WiFi, high-signal glyph reused as the home tile's static icon (the
// tile doesn't show a live signal tier the way the bar's own badge
// does) -- same three-tier family the bar module already uses.
pub const WIFI: &str = "\u{E4EA}";
pub const WIFI_SLASH: &str = "\u{E4F2}"; // WiFi tile, radio off

// Home-page action tiles (Control Center redesign, see the project
// plan) -- codepoints fetched fresh from phosphor-icons/core's
// src/icons.ts, not guessed (same discipline as every other glyph here).
pub const MOON: &str = "\u{E1F6}"; // Night mode tile
pub const CAMERA: &str = "\u{E10E}"; // Screenshot tile
pub const AIRPLANE: &str = "\u{E002}"; // Airplane mode tile

pub const MAGNIFYING_GLASS: &str = "\u{E30C}"; // Search/filter field
pub const GEAR: &str = "\u{E270}"; // Per-row "configure" button -> detail page
pub const CARET_LEFT: &str = "\u{E138}"; // Detail page's back button

use gtk4::{self as gtk, prelude::*, Orientation};

/// A single Phosphor glyph, styled via the `.balise-icon` CSS class --
/// for icon-only buttons (close/dismiss) or standalone indicators (the
/// lock icon on a secured network row, the error toast's warning icon).
pub fn icon_label(glyph: &str) -> gtk::Label {
    gtk::Label::builder().label(glyph).css_classes(["balise-icon"]).build()
}

/// Icon + text side by side, for buttons that used to combine
/// `.icon_name(...)` with `.label(...)` -- GTK's built-in icon+label
/// button layout only works with registered icon-theme names, not a
/// custom font glyph, so this builds the equivalent by hand.
pub fn icon_text_button(glyph: &str, text: &str, css_classes: &[&str]) -> gtk::Button {
    let content = gtk::Box::builder().orientation(Orientation::Horizontal).spacing(6).halign(gtk::Align::Center).build();
    content.append(&icon_label(glyph));
    content.append(&gtk::Label::new(Some(text)));

    gtk::Button::builder().child(&content).css_classes(css_classes).build()
}
