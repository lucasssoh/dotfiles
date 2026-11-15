//! Loads Roue's CSS theme: fallback built into the binary, overridden by
//! the user file if present. Same mechanism as prisme-src/src/theme.rs
//! (see its doc for the full reasoning).

/// Fallback theme, identical to roue/style.css -- copied here for the
/// same reason as in Prisme: `config/hyprland/roue/style.css` lives outside
/// `roue-src/`, which install.sh copies alone into `~/.cache/roue-build/`
/// before `cargo build`.
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
    background-color: rgba(18, 18, 22, 0.42);
    backdrop-filter: blur(20px);
}

window.light,
.background.light {
    background-color: rgba(245, 243, 238, 0.32);
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
///      THIS wheel, absent = the general rule applies as-is.
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
