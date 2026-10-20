//! Loads Prisme's CSS theme: fallback built into the binary, overridden by
//! the user file if present.

/// Fallback theme, the same rules as config/hyprland/prisme/style.css --
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
    font-family: "MiSans Latin";
}

*:focus,
*:focus-visible {
    outline: none;
}

window,
.background {
    background-color: rgba(18, 18, 22, 0.42);
}

/* The preview and its caption, bare on the blurred desktop, centred above
   the cards. */

.prisme-legend {
    margin-top: 18px;
    color: #f2f2f7;
}

.prisme-name {
    font-size: 30px;
    font-weight: 500;
    color: #f2f2f7;
}

.prisme-details {
    font-size: 15px;
    color: rgba(242, 242, 247, 0.6);
    margin-top: 4px;
}

/* The light/dark toggle of a pair: two quiet words, the half on screen
   lit. Clickable, like C. */
.prisme-halves {
    margin-top: 6px;
}

.prisme-half,
.prisme-half-on {
    font-size: 14px;
    padding: 2px 0 2px 14px;
    transition: color 200ms ease;
}

.prisme-half {
    color: rgba(242, 242, 247, 0.4);
}

.prisme-half:hover {
    color: rgba(242, 242, 247, 0.72);
}

.prisme-half-on {
    color: #f2f2f7;
}

.prisme-bar {
    padding: 0 40px 22px 40px;
    color: #a1a1a6;
    font-size: 14px;
    font-feature-settings: "tnum";
    text-shadow: 0 1px 8px rgba(0, 0, 0, 0.35);
}

.prisme-hint {
    color: #d1d1d6;
    transition: opacity 600ms ease-out;
}

.prisme-hint.faded {
    opacity: 0;
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
