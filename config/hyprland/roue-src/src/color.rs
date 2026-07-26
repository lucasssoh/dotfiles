//! Résolution de la couleur d'accent d'un secteur (champ TOML optionnel
//! `accent`, cf. config.rs) -- couleurs nommées connues ou code hex direct
//! `#rrggbb`, repli sur le cyan historique si absent/inconnu. Point central
//! pour que toute future roue puisse définir ses propres teintes par
//! secteur juste via son fichier TOML, sans toucher au code Rust (cf.
//! wheels/powerprofile.toml pour un exemple : vert/jaune/cyan).

const DEFAULT_HEX: &str = "#4fefff";

/// Couleur canonique résolue pour un secteur -- code hex (sert à rasteriser
/// la variante "accent" de son icône SVG, cf. icons.rs) ET la même couleur
/// décomposée en RGB `f32` (sert à teindre le remplissage du secteur et le
/// texte, cf. wheel.rs). Les deux DOIVENT venir de la même résolution, sinon
/// l'icône et le reste du secteur divergeraient légèrement de teinte.
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

/// Palette de noms courts utilisables dans le TOML -- volontairement petite
/// (les teintes qu'on utilise vraiment aujourd'hui : cyan par défaut,
/// vert/jaune pour powerprofile, rouge pour le sous-menu de confirmation
/// de power). Un code hex direct (`accent = "#34d399"`) reste toujours
/// possible pour tout le reste, aucune roue future n'est limitée à ces noms.
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
