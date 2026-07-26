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
    background-color: rgba(20, 20, 20, 0.95);
}

/* rgba(20, 20, 22, 0.88) reprend exactement la couleur du moyeu central
   (cf. HUB fill dans roue-src/src/wheel.rs), #505050 la bordure des modules
   waybar (@overlay2, cf. waybar/style.css) -- panneau plutôt qu'un blur
   plein écran (coût GPU permanent au repos, cf. discussion). */
.roue-sidebar {
    background-color: rgba(20, 20, 22, 0.88);
    border: 1px solid #505050;
    border-radius: 8px;
    padding: 16px 22px;
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

/// Charge le CSS en 3 couches, chacune par-dessus la précédente à la MÊME
/// priorité (STYLE_PROVIDER_PRIORITY_USER) -- à priorité égale, GTK fait
/// gagner le dernier provider ajouté sur les propriétés en conflit, donc
/// l'ordre d'appel ci-dessous EST la règle de cascade :
///   1. fallback intégré au binaire -- l'app reste utilisable même en
///      lancement direct hors install.sh (cargo run).
///   2. `roue/style.css` -- règle générale, commune à toutes les roues
///      (symlinké par install.sh vers ~/.config/roue/).
///   3. `roue/wheels/<wheel_name>.css`, optionnel -- surcharge propre à
///      CETTE roue (ex. couleur de fond différente pour power vs
///      powerprofile), absent = la règle générale s'applique telle quelle.
pub fn load(display: &gtk4::gdk::Display, wheel_name: &str) {
    let fallback = gtk4::CssProvider::new();
    fallback.load_from_string(FALLBACK_CSS);
    gtk4::style_context_add_provider_for_display(
        display,
        &fallback,
        gtk4::STYLE_PROVIDER_PRIORITY_USER,
    );

    load_if_exists(display, user_style_path());
    load_if_exists(display, wheel_style_path(wheel_name));
}

fn load_if_exists(display: &gtk4::gdk::Display, path: Option<std::path::PathBuf>) {
    let Some(path) = path else { return };
    if !path.exists() {
        return;
    }
    let provider = gtk4::CssProvider::new();
    provider.load_from_path(&path);
    gtk4::style_context_add_provider_for_display(
        display,
        &provider,
        gtk4::STYLE_PROVIDER_PRIORITY_USER,
    );
}

fn user_style_path() -> Option<std::path::PathBuf> {
    let home = std::env::var("HOME").ok()?;
    Some(std::path::PathBuf::from(home).join(".config/roue/style.css"))
}

fn wheel_style_path(wheel_name: &str) -> Option<std::path::PathBuf> {
    let home = std::env::var("HOME").ok()?;
    Some(std::path::PathBuf::from(home).join(format!(".config/roue/wheels/{wheel_name}.css")))
}
