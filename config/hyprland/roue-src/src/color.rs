//! Resolves a sector's accent color (optional TOML field `accent`, see
//! config.rs) -- known named colors or a direct `#rrggbb` hex code, falling
//! back to the historical cyan if absent/unknown. Central place so any
//! future wheel can define its own per-sector tints just through its TOML
//! file, without touching the Rust code (see wheels/powerprofile.toml for
//! an example: green/yellow/cyan).

const DEFAULT_HEX: &str = "#4fefff";

/// Canonical color resolved for a sector -- a hex code (used to rasterize
/// the "accent" variant of its SVG icon, see icons.rs) AND the same color
/// decomposed into `f32` RGB (used to tint the sector's fill and text, see
/// wheel.rs). Both MUST come from the same resolution, otherwise the icon
/// and the rest of the sector would drift slightly apart in tint.
pub struct Accent {
    pub hex: String,
    pub rgb: (f32, f32, f32),
}

pub fn resolve(accent: Option<&str>) -> Accent {
    let hex = resolve_hex(accent);
    let rgb = parse_hex(&hex).unwrap_or_else(|| parse_hex(DEFAULT_HEX).unwrap());
    Accent { hex, rgb }
}

fn resolve_hex(accent: Option<&str>) -> String {
    let Some(raw) = accent else { return DEFAULT_HEX.to_string() };
    let raw = raw.trim().to_ascii_lowercase();
    if raw.starts_with('#') {
        return raw;
    }
    named(&raw).unwrap_or(DEFAULT_HEX).to_string()
}

/// Palette of short names usable in the TOML -- deliberately small (the
/// tints actually used today: cyan by default, green/yellow for
/// powerprofile, red for power's confirmation sub-menu). A direct hex code
/// (`accent = "#34d399"`) always remains possible for everything else, no
/// future wheel is limited to these names.
fn named(name: &str) -> Option<&'static str> {
    match name {
        "cyan" | "blue" | "default" => Some(DEFAULT_HEX),
        "green" => Some("#4ade80"),
        "yellow" => Some("#fbbf24"),
        "red" => Some("#ff5252"),
        _ => None,
    }
}

fn parse_hex(hex: &str) -> Option<(f32, f32, f32)> {
    let s = hex.strip_prefix('#')?;
    if s.len() != 6 {
        return None;
    }
    let r = u8::from_str_radix(&s[0..2], 16).ok()?;
    let g = u8::from_str_radix(&s[2..4], 16).ok()?;
    let b = u8::from_str_radix(&s[4..6], 16).ok()?;
    Some((r as f32 / 255.0, g as f32 / 255.0, b as f32 / 255.0))
}
