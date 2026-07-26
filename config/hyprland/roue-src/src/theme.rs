//! Chargement du thème CSS de Roue : fallback intégré au binaire, surchargé
//! par le fichier utilisateur si présent. Même mécanisme que
//! prisme-src/src/theme.rs (voir sa doc pour le détail du raisonnement).

/// Palette de secours, identique à waybar/style.css, orbit/theme.toml et
/// prisme/style.css -- recopiée ici en dur pour la même raison que dans
/// Prisme : `config/hyprland/roue/style.css` vit hors de `roue-src/`,
/// qu'install.sh copie seul dans `~/.cache/roue-build/` avant `cargo build`.
const FALLBACK_CSS: &str = r#"
* {
    font-family: "JetBrains Mono";
}

*:focus,
*:focus-visible {
    outline: none;
}

window,
.background {
    background-color: rgba(20, 20, 20, 0.55);
}

.roue-footer {
    border-top: 1px solid #505050;
    padding: 10px 24px;
}

.roue-title {
    font-weight: bold;
    font-size: 1.1em;
    color: #f2f2f7;
}

.roue-hint {
    color: #8e8e93;
    font-size: 0.9em;
}
"#;

/// Charge le CSS externe (symlinké par install.sh depuis
/// config/hyprland/roue/ vers ~/.config/roue/) par-dessus un fallback
/// intégré au binaire -- l'app reste utilisable même en lancement direct
/// hors install.sh (cargo run). Priorité STYLE_PROVIDER_PRIORITY_USER pour
/// les deux (comme Prisme/Orbit), sinon Adwaita gagne sur le fond.
pub fn load(display: &gtk4::gdk::Display) {
    let fallback = gtk4::CssProvider::new();
    fallback.load_from_string(FALLBACK_CSS);
    gtk4::style_context_add_provider_for_display(
        display,
        &fallback,
        gtk4::STYLE_PROVIDER_PRIORITY_USER,
    );

    if let Some(path) = user_style_path() {
        if path.exists() {
            let user = gtk4::CssProvider::new();
            user.load_from_path(&path);
            gtk4::style_context_add_provider_for_display(
                display,
                &user,
                gtk4::STYLE_PROVIDER_PRIORITY_USER,
            );
        }
    }
}

fn user_style_path() -> Option<std::path::PathBuf> {
    let home = std::env::var("HOME").ok()?;
    Some(std::path::PathBuf::from(home).join(".config/roue/style.css"))
}
