//! Loads Prisme's CSS theme: fallback built into the binary, overridden by
//! the user file if present.

/// Fallback palette, identical to waybar/style.css and orbit/theme.toml --
/// used if ~/.config/prisme/style.css doesn't exist yet (before
/// install.sh, or running the binary directly from prisme-src/ during
/// development). Copied here as a hardcoded string rather than
/// `include_str!`-ed from the external file (config/hyprland/prisme/
/// style.css): the latter lives OUTSIDE prisme-src/, which install.sh
/// copies alone into ~/.cache/prisme-build/ before `cargo build` (same
/// scheme as Orbit's vendoring) -- a relative path `../../prisme/
/// style.css` resolves to nothing there. The real theme, editable without
/// recompiling, stays `config/hyprland/prisme/style.css` (symlinked to
/// ~/.config/prisme/ by install.sh): this constant only needs to be a
/// correct safety net, not the source of truth.
const FALLBACK_CSS: &str = r#"
* {
    font-family: "Inter";
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

/// Loads the external CSS (symlinked by install.sh from
/// config/hyprland/prisme/ to ~/.config/prisme/, same convention as Orbit)
/// on top of a fallback built into the binary -- the app stays usable even
/// launched directly outside install.sh (cargo run).
///
/// STYLE_PROVIDER_PRIORITY_USER for both (like Orbit): the system theme
/// (Adwaita) is applied at a lower priority and would otherwise win over
/// our background rules (the background stayed transparent -- checked live
/// via screenshot before this fix).
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

/// Location of the user CSS, symlinked by install.sh from
/// config/hyprland/prisme/style.css.
fn user_style_path() -> Option<std::path::PathBuf> {
    let home = std::env::var("HOME").ok()?;
    Some(std::path::PathBuf::from(home).join(".config/prisme/style.css"))
}
