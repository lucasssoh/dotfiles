//! Chargement du thème CSS de Prisme : fallback intégré au binaire,
//! surchargé par le fichier utilisateur si présent.

/// Palette de secours, identique à waybar/style.css et orbit/theme.toml --
/// utilisée si ~/.config/prisme/style.css n'existe pas encore (avant
/// install.sh, ou en lançant le binaire directement depuis prisme-src/ pour
/// développer). Recopiée ici en dur plutôt qu'`include_str!` du fichier
/// externe (config/hyprland/prisme/style.css) : ce dernier vit HORS de
/// prisme-src/, qu'install.sh copie seul dans ~/.cache/prisme-build/ avant
/// `cargo build` (même schéma que le vendoring d'Orbit) -- un chemin relatif
/// `../../prisme/style.css` s'y résout dans le vide. Le vrai thème,
/// éditable sans recompiler, reste `config/hyprland/prisme/style.css`
/// (symlinké vers ~/.config/prisme/ par install.sh) : cette constante n'a
/// besoin d'être qu'un filet de secours correct, pas la source de vérité.
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
    background-color: rgba(20, 20, 20, 0.72);
}

.prisme-header,
.prisme-footer {
    color: #f2f2f7;
}

.prisme-header {
    border-bottom: 1px solid #505050;
    padding: 14px 24px;
}

.prisme-footer {
    border-top: 1px solid #505050;
    padding: 10px 24px;
    color: #8e8e93;
    font-size: 0.9em;
}

.prisme-title {
    font-weight: bold;
    font-size: 1.1em;
    color: #f2f2f7;
}

.prisme-hint {
    color: #8e8e93;
    font-size: 0.9em;
}

.prisme-mode-toggle {
    background-color: transparent;
    background-image: none;
    color: #8e8e93;
    border: 1px solid #505050;
    border-radius: 6px;
    box-shadow: none;
    padding: 4px 14px;
}

.prisme-mode-toggle:checked {
    background-color: #2c2c2e;
    color: #4fefff;
    border-color: #4fefff;
}

.prisme-duration-chip {
    color: #8e8e93;
    border: 1px solid #505050;
    border-radius: 6px;
    padding: 4px 10px;
}
"#;

/// Charge le CSS externe (symlinké par install.sh depuis config/hyprland/prisme/
/// vers ~/.config/prisme/, même convention qu'Orbit) par-dessus un fallback
/// intégré au binaire -- l'app reste utilisable même en lancement direct hors
/// install.sh (cargo run).
///
/// Priorité STYLE_PROVIDER_PRIORITY_USER pour les deux (comme Orbit) : le
/// thème système (Adwaita) est appliqué à une priorité inférieure et sinon
/// gagnerait sur nos règles de fond (le fond restait transparent -- vérifié
/// en live via capture d'écran avant ce fix).
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

/// Emplacement du CSS utilisateur, symlinké par install.sh depuis
/// config/hyprland/prisme/style.css.
fn user_style_path() -> Option<std::path::PathBuf> {
    let home = std::env::var("HOME").ok()?;
    Some(std::path::PathBuf::from(home).join(".config/prisme/style.css"))
}
