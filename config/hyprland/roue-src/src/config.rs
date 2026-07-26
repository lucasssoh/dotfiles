//! Chargement de la définition d'une roue depuis
//! `~/.config/roue/wheels/<nom>.toml` -- même format que `orbit/theme.toml`.
//! Ajouter une nouvelle roue ne demande donc aucun changement de code Rust :
//! juste un nouveau fichier ici et un déclencheur (raccourci clavier, clic
//! waybar...) qui lance `roue <nom>`.

use serde::Deserialize;
use std::path::PathBuf;

#[derive(Deserialize)]
pub struct WheelConfig {
    pub title: String,
    #[serde(rename = "segment")]
    pub segments: Vec<Segment>,
}

#[derive(Deserialize, Clone)]
pub struct Segment {
    pub icon: String,
    pub label: String,
    pub action: String,
    /// Secteur destructif -- valider ce secteur bascule d'abord la roue sur
    /// un choix Confirmer/Annuler au lieu de lancer l'action tout de suite
    /// (cf. wheel.rs). Absent du TOML = false.
    #[serde(default)]
    pub confirm: bool,
}

fn wheels_dir() -> PathBuf {
    let home = std::env::var("HOME").expect("HOME non défini");
    PathBuf::from(home).join(".config/roue/wheels")
}

/// Charge la définition de la roue `name`. Échec fatal (fichier absent ou
/// TOML invalide) : contrairement au clavier de Prisme (`keymap.conf`, où une
/// ligne invalide est juste ignorée), une roue sans secteurs n'a rien à
/// afficher -- pas de repli sensé.
pub fn load(name: &str) -> WheelConfig {
    let path = wheels_dir().join(format!("{name}.toml"));
    let content = std::fs::read_to_string(&path).unwrap_or_else(|e| {
        eprintln!("[roue] impossible de lire {path:?}: {e}");
        std::process::exit(1);
    });
    toml::from_str(&content).unwrap_or_else(|e| {
        eprintln!("[roue] {path:?} invalide: {e}");
        std::process::exit(1);
    })
}
