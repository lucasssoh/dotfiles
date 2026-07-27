//! Loads Roue's CSS theme: fallback built into the binary, overridden by
//! the user file if present. Same mechanism as prisme-src/src/theme.rs
//! (see its doc for the full reasoning).

/// Fallback palette, identical to waybar/style.css, orbit/theme.toml, and
/// prisme/style.css -- copied here as a hardcoded string for the same
/// reason as in Prisme: `config/hyprland/roue/style.css` lives outside
/// `roue-src/`, which install.sh copies alone into `~/.cache/roue-build/`
/// before `cargo build`.
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

/* rgba(20, 20, 22, 0.88) exactly matches the hub's fill color (see the HUB
   fill in roue-src/src/wheel.rs), #505050 the waybar modules' border
   (@overlay2, see waybar/style.css) -- a panel rather than a full-screen
   blur (permanent GPU cost at rest, see discussion). */
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

/// Loads CSS in 3 layers, each one on top of the previous at the SAME
/// priority (STYLE_PROVIDER_PRIORITY_USER) -- at equal priority, GTK lets
/// the last-added provider win on conflicting properties, so the call
/// order below IS the cascade rule:
///   1. fallback built into the binary -- the app stays usable even when
///      launched directly outside install.sh (cargo run).
///   2. `roue/style.css` -- general rule, shared by all wheels (symlinked
///      by install.sh into ~/.config/roue/).
///   3. `roue/wheels/<wheel_name>.css`, optional -- override specific to
///      THIS wheel (e.g. a different background color for power vs
///      powerprofile), absent = the general rule applies as-is.
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
