//! Loads Balise's CSS theme: a fallback built into the binary, overridden
//! by the user file if present. Two-layer cascade, no TOML->generate_css()
//! step -- that's Orbit-specific (upstream, theme.rs there is ~715 lines);
//! Prisme and Roue don't need it and neither does Balise. Copied from
//! prisme-src/src/theme.rs's pattern almost verbatim.

/// Fallback palette/panel, matching the rest of the system's "verre
/// givré" material (hypr/hyprland.lua's active-window border gradient,
/// roue/style.css's .roue-sidebar, swaync/style.css's .control-center,
/// orbit/style.css's .orbit-panel) -- used if ~/.config/balise/style.css
/// doesn't exist yet (before install.sh, or running the binary directly
/// during development). Copied here as a hardcoded string rather than
/// `include_str!`-ed from the external file (config/hyprland/balise/
/// style.css): that file lives OUTSIDE balise-src/, which install.sh
/// copies alone into ~/.cache/balise-build/ before `cargo build` (same
/// scheme as Orbit/Prisme/Roue's vendoring/building) -- a relative path
/// `../../balise/style.css` resolves to nothing there. The real theme,
/// editable without recompiling, is config/hyprland/balise/style.css
/// (symlinked to ~/.config/balise/ by install.sh once Balise reaches
/// Phase 5's cutover): this constant only needs to be a correct safety
/// net, not the source of truth.
const FALLBACK_CSS: &str = r#"
* {
    font-family: "Inter";
}

*:focus,
*:focus-visible {
    outline: none;
}

/* GTK's built-in ".background" class paints an opaque themed rectangle
   that ignores border-radius -- confirmed live on Orbit this session (a
   right-angle corner poking past its rounded panel once its compositor
   blur was removed). Balise's window never adds that class in the first
   place (see ui/window.rs); this is belt-and-braces in case some GTK/
   theme path re-adds an opaque fill regardless. */
window,
.background {
    background-color: transparent;
    background-image: none;
    box-shadow: none;
    border-radius: 16px;
}

/* Border: the SAME "curved glass" treatment as Hyprland's active-window
   border, RoueWheel's hub rim, .roue-sidebar, swaync's .control-center and
   (now-fixed) .orbit-panel -- one material read across the whole system.
   LONGHAND background-image + background-clip, NOT the inline
   `background: <gradient> padding-box, <gradient> border-box` shorthand:
   that shorthand renders fine on .roue-sidebar/.control-center, but on
   Orbit's panel/surface combination it made GTK draw the corners as a
   right angle instead of following border-radius (confirmed live via a
   cropped/zoomed screenshot of the real surface corner). The longhand
   produces the identical visual result and rounds correctly everywhere --
   do not "simplify" this back to the shorthand.

   Fill opacity 0.97: there is no compositor blur behind Balise (no
   layer_rule for the "balise" namespace in hypr/windowrules.lua, matching
   Orbit's current no-blur state), so legibility rests entirely on this
   near-opaque fill -- 0.97 is the value validated live on Orbit against an
   unblurred backdrop this same session. */
.balise-panel {
    border: 1.5px solid transparent;
    border-radius: 16px;
    background-image:
        linear-gradient(rgba(12, 12, 14, 0.97), rgba(12, 12, 14, 0.97)),
        linear-gradient(
            135deg,
            rgba(229, 229, 234, 0.75) 0%,
            rgba(142, 142, 147, 0.45) 25%,
            rgba(99, 99, 102, 0.28) 50%,
            rgba(58, 58, 60, 0.15) 75%,
            rgba(28, 28, 30, 0.06) 100%
        );
    background-clip: padding-box, border-box;
    box-shadow: 0 8px 32px rgba(0, 0, 0, 0.45);
    padding: 14px;
}

.balise-header {
    color: #f2f2f7;
}

.balise-title {
    font-weight: bold;
    font-size: 1.1em;
    color: #f2f2f7;
}

.balise-hint {
    color: #8e8e93;
    font-size: 0.9em;
}
"#;

/// Loads the external CSS (symlinked by install.sh from
/// config/hyprland/balise/ to ~/.config/balise/ once Balise reaches
/// Phase 5's cutover, same convention as Orbit/Prisme/Roue -- see
/// crate::paths for the BALISE_CONFIG_DIR development override) on top of
/// a fallback built into the binary. Both at STYLE_PROVIDER_PRIORITY_USER
/// (like every sibling app): the system theme (Adwaita) is applied at a
/// lower priority and would otherwise win over our background rules.
///
/// Returns the two providers so `reload()` can refresh just the user
/// layer later (`balise reload-theme`) without restarting the process.
pub fn load(display: &gtk4::gdk::Display) -> (gtk4::CssProvider, gtk4::CssProvider) {
    let fallback = gtk4::CssProvider::new();
    fallback.load_from_string(FALLBACK_CSS);
    gtk4::style_context_add_provider_for_display(
        display,
        &fallback,
        gtk4::STYLE_PROVIDER_PRIORITY_USER,
    );

    let user = gtk4::CssProvider::new();
    load_user_css(&user);
    gtk4::style_context_add_provider_for_display(display, &user, gtk4::STYLE_PROVIDER_PRIORITY_USER);

    (fallback, user)
}

/// Re-reads ~/.config/balise/style.css into the user provider. If the
/// file has been removed since startup, clears the provider back to empty
/// rather than leaving stale rules in place -- same behavior as Orbit's
/// `apply_theme` (orbit-vendor/src/ui/window.rs).
pub fn reload(user: &gtk4::CssProvider) {
    load_user_css(user);
}

fn load_user_css(provider: &gtk4::CssProvider) {
    let path = crate::paths::style_file();
    if path.exists() {
        provider.load_from_path(&path);
    } else {
        provider.load_from_string("");
    }
}
