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

/* Border, take two. The "background-clip: padding-box, border-box"
   longhand trick (works for Orbit/Roue/swaync -- see their own style.css
   files) rendered NOTHING in the border-box ring here: confirmed at the
   pixel level (sampled the raw screenshot buffer) that the ring was flat
   black with zero gradient pixels at border-width 2.5px, and even at a
   diagnostic 20px the ring stayed solid black while the window DID grow
   to make room for it (border-width was respected, the content just
   never painted). Rather than chase why this one surface/widget
   combination breaks the clip trick, switched to the classically robust
   way to fake a gradient border in CSS: two nested boxes (see
   ui/window.rs). `.balise-panel` (outer) is the gradient itself, a
   single plain `background` filling its whole rounded rect --
   `.balise-panel-inner` sits inside it with a small margin (below), and
   that uncovered margin ring IS the border, with no clip-box ambiguity
   possible. */
.balise-panel {
    border-radius: 16px;
    background: linear-gradient(
        135deg,
        rgba(234, 234, 238, 0.9) 0%,
        rgba(170, 172, 180, 0.65) 25%,
        rgba(130, 132, 140, 0.45) 50%,
        rgba(90, 92, 98, 0.3) 75%,
        rgba(60, 62, 68, 0.18) 100%
    );
    box-shadow: 0 8px 32px rgba(0, 0, 0, 0.45);
}

/* No compositor blur behind Balise (added and removed three times this
   session -- see hypr/windowrules.lua's header comment; settled on never
   reinstating it). The "glass" read is built from color alone here: a
   gradient fill instead of the previous flat rgba(40,40,45,0.72), same
   135deg direction as the outer border, lighter/bluer at the top-left
   fading to a plain darker gray at the bottom-right -- mimics a light
   source hitting a glass pane rather than a uniform tinted pane. Alpha
   stays in a tight 0.88-0.92 band throughout (not varied alongside the
   color) so no part of the panel looks more see-through than another --
   with no blur to soften it, an uneven bleed-through of whatever's
   behind would read as a flaw, not glass.

   margin: 1.5px matches swaync's .control-center border width (this
   session's earlier 3px read as heavier than the rest of the system's
   glass panels). border-radius 14.5px (16 - 1.5) keeps the inner corner
   concentric with the outer one. */
.balise-panel-inner {
    background: linear-gradient(
        135deg,
        rgba(60, 62, 70, 0.88) 0%,
        rgba(42, 43, 49, 0.9) 45%,
        rgba(26, 26, 30, 0.92) 100%
    );
    border-radius: 14.5px;
    margin: 1.5px;
    /* Global padding: more breathing room between the border and the
       content than the previous cramped 14px. */
    padding: 20px;
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

/* Rows, buttons, lists, switches, overlays -- kept in sync with
   config/hyprland/balise/style.css (the real source of truth, see this
   file's own header comment for why this fallback exists at all).
   Gradient fills in the panel's own 135deg light direction, real
   glass-bordered rows/overlays for the active network and password/error
   dialogs, 10px rounded-rect buttons -- matching Roue's "verre" quality
   rather than Orbit's flat 9999px-pill generated theme. */

.balise-search-container {
    background: rgba(255, 255, 255, 0.03);
    border: 1px solid rgba(255, 255, 255, 0.05);
    border-radius: 12px;
    padding: 2px;
}

.balise-search-entry {
    background: transparent;
    border: none;
    box-shadow: none;
    color: #f2f2f7;
    font-size: 12px;
}

.balise-search-entry > text {
    caret-color: #a8b4c4;
}

.balise-section-header {
    font-size: 10px;
    text-transform: uppercase;
    letter-spacing: 0.12em;
    color: #8e8e93;
    font-weight: 700;
    padding: 14px 12px 4px 12px;
}

.balise-placeholder {
    color: #f2f2f7;
    opacity: 0.5;
    font-size: 13px;
    font-style: italic;
    padding: 32px 16px;
}

.balise-network-row,
.balise-saved-network-row {
    background-image: linear-gradient(135deg, rgba(255, 255, 255, 0.11), rgba(255, 255, 255, 0.04));
    border: 1px solid rgba(255, 255, 255, 0.08);
    border-radius: 14px;
    padding: 10px 12px;
    margin: 4px 6px;
    transition: background-color 0.25s cubic-bezier(0.4, 0, 0.2, 1),
        border-color 0.25s cubic-bezier(0.4, 0, 0.2, 1);
}

.balise-network-row:hover,
.balise-saved-network-row:hover {
    background-image: linear-gradient(135deg, rgba(255, 255, 255, 0.18), rgba(255, 255, 255, 0.07));
    border-color: #a8b4c4;
}

.balise-network-row.connected,
.balise-saved-network-row.active {
    border: 1.5px solid transparent;
    border-radius: 14px;
    background-image:
        linear-gradient(135deg, rgba(168, 180, 196, 0.22), rgba(168, 180, 196, 0.10)),
        linear-gradient(
            135deg,
            rgba(232, 236, 240, 0.65) 0%,
            rgba(168, 180, 196, 0.35) 50%,
            rgba(60, 64, 70, 0.12) 100%
        );
    background-clip: padding-box, border-box;
}

.balise-network-row.focused,
.balise-saved-network-row.focused {
    border-color: #a8b4c4;
    box-shadow: 0 0 0 2px rgba(168, 180, 196, 0.3);
}

.balise-ssid {
    font-weight: 700;
    font-size: 13px;
    color: #f2f2f7;
}

.balise-status {
    font-size: 11px;
    color: #f2f2f7;
    opacity: 0.6;
}

.balise-status-accent {
    color: #a8b4c4;
    opacity: 0.9;
    font-weight: 600;
}

.balise-signal-icon,
.balise-detail-label {
    color: #f2f2f7;
    opacity: 0.5;
}

/* Phosphor glyphs (see ui/icon.rs) -- the same icon font the quickshell
   bar uses everywhere (Fonts.qml's iconPhosphor), instead of GTK's system
   icon-theme lookups Balise used at first, which drew from a different,
   mismatched icon language. */
.balise-icon {
    font-family: "Phosphor";
    font-size: 14px;
}

.balise-icon-accent {
    color: #a8b4c4;
}

.balise-signal-bar-active {
    background-color: #f2f2f7;
    opacity: 0.7;
    border-radius: 1px;
}

.balise-signal-bar-active-accent {
    background-color: #a8b4c4;
    border-radius: 1px;
}

.balise-signal-bar-inactive {
    background-color: #f2f2f7;
    opacity: 0.15;
    border-radius: 1px;
}

.balise-signal-bars-pad {
    padding: 2px;
}

.balise-icon-container {
    background-color: rgba(168, 180, 196, 0.3);
    border-radius: 8px;
    padding: 6px;
}

.balise-working-indicator {
    opacity: 0.8;
}

.balise-button {
    background-image: linear-gradient(135deg, rgba(255, 255, 255, 0.14), rgba(255, 255, 255, 0.05));
    color: #f2f2f7;
    border: 1px solid rgba(255, 255, 255, 0.12);
    border-radius: 10px;
    padding: 6px 16px;
    font-size: 11px;
    font-weight: 700;
    box-shadow: none;
    min-height: 0;
    min-width: 0;
    transition: background-color 0.2s ease, border-color 0.2s ease, color 0.2s ease;
}

.balise-button:hover {
    background-image: linear-gradient(135deg, rgba(200, 208, 220, 0.55), rgba(168, 180, 196, 0.32));
    border-color: #a8b4c4;
    color: #f2f2f7;
}

/* No glow (box-shadow) on primary/destructive -- inconsistent with the
   rest of the "glass" material, which reads through gradient fill + a
   thin border, never a diffuse colored halo. A visible border replaces
   the previous "1px solid transparent" (which left these two variants
   without the crisp edge every other button/card in the panel has).
   Translucent accent/danger-tinted glass instead of a solid light fill
   (which clashed once the panel itself became a lighter, more
   translucent gray -- two similarly-light, fully opaque surfaces next to
   each other stopped reading as distinct materials). Text stays light
   (#f2f2f7 / #ffffff) since the fill is no longer solid light. */
.balise-button.primary {
    background-image: linear-gradient(135deg, rgba(200, 208, 220, 0.55), rgba(168, 180, 196, 0.32));
    color: #f2f2f7;
    border: 1px solid rgba(255, 255, 255, 0.35);
    box-shadow: none;
}

.balise-button.primary label {
    color: #f2f2f7;
}

.balise-button.primary:hover {
    background-image: linear-gradient(135deg, rgba(210, 217, 227, 0.65), rgba(184, 194, 208, 0.4));
    color: #f2f2f7;
}

.balise-button.destructive {
    background-image: linear-gradient(135deg, rgba(255, 154, 154, 0.55), rgba(255, 110, 110, 0.35));
    color: #ffffff;
    border: 1px solid rgba(255, 255, 255, 0.35);
    box-shadow: none;
}

.balise-button.destructive:hover {
    background-image: linear-gradient(135deg, rgba(255, 174, 174, 0.65), rgba(255, 138, 138, 0.42));
    color: #ffffff;
}

/* Power toggle switch -- glass, same language as the buttons/panel:
   gradient fills (135deg) instead of flat colors, translucent even when
   checked (was a solid #a8b4c4) so it reads as the same material as
   everything else instead of a plain colored pill. */
window switch.balise-toggle-switch,
window switch.balise-toggle-switch:not(:backdrop),
window switch.balise-toggle-switch trough,
window switch.balise-toggle-switch:not(:backdrop) trough {
    background-image: linear-gradient(135deg, rgba(255, 255, 255, 0.2), rgba(255, 255, 255, 0.07));
    border: 1px solid rgba(255, 255, 255, 0.16);
    box-shadow: none;
    border-radius: 9999px;
    min-width: 40px;
    min-height: 22px;
}

window switch.balise-toggle-switch:checked,
window switch.balise-toggle-switch:checked:not(:backdrop),
window switch.balise-toggle-switch:checked:hover,
window switch.balise-toggle-switch:checked trough,
window switch.balise-toggle-switch:checked:not(:backdrop) trough {
    background-image: linear-gradient(135deg, rgba(200, 208, 220, 0.6), rgba(168, 180, 196, 0.4));
    border-color: rgba(255, 255, 255, 0.4);
    box-shadow: none;
}

/* Slider stays a light "glass pebble" in both states -- a gradient
   instead of flat white, with a soft edge instead of the plain white ->
   dark-flip the solid-fill version needed for contrast. */
window switch.balise-toggle-switch slider {
    background-image: linear-gradient(135deg, #ffffff, #d8dce2);
    border: 1px solid rgba(255, 255, 255, 0.5);
    border-radius: 9999px;
    box-shadow: 0 1px 3px rgba(0, 0, 0, 0.4);
    min-width: 16px;
    min-height: 16px;
    margin: 3px;
}

window switch.balise-toggle-switch:checked slider,
window switch.balise-toggle-switch:checked:not(:backdrop) slider {
    background-image: linear-gradient(135deg, #ffffff, #c2cbd6);
}

entry,
password-entry {
    background-color: rgba(255, 255, 255, 0.05);
    border: 1px solid rgba(255, 255, 255, 0.1);
    color: #f2f2f7;
    border-radius: 12px;
    padding: 8px 12px;
    min-height: 18px;
}

password-entry > text {
    margin-left: 8px;
    margin-right: 8px;
}

entry:focus,
password-entry:focus {
    border-color: #a8b4c4;
    box-shadow: 0 0 0 1px #a8b4c4;
}

.balise-password-overlay {
    border: 1.5px solid transparent;
    border-radius: 16px;
    background-image:
        linear-gradient(rgba(12, 12, 14, 0.99), rgba(12, 12, 14, 0.99)),
        linear-gradient(
            135deg,
            rgba(232, 236, 240, 0.7) 0%,
            rgba(168, 180, 196, 0.4) 50%,
            rgba(60, 64, 70, 0.15) 100%
        );
    background-clip: padding-box, border-box;
    box-shadow: 0 8px 32px rgba(0, 0, 0, 0.6);
    color: #f2f2f7;
    margin: 12px;
    padding: 16px;
}

.balise-password-overlay label {
    color: #f2f2f7;
}

.balise-error-text-small {
    color: #ff6e6e;
    font-size: 12px;
    font-weight: 500;
}

.balise-error-overlay {
    border: 1.5px solid transparent;
    border-radius: 16px;
    background-image:
        linear-gradient(rgba(12, 12, 14, 0.99), rgba(12, 12, 14, 0.99)),
        linear-gradient(
            135deg,
            rgba(255, 190, 190, 0.7) 0%,
            rgba(255, 110, 110, 0.4) 50%,
            rgba(90, 40, 40, 0.15) 100%
        );
    background-clip: padding-box, border-box;
    box-shadow: 0 8px 32px rgba(0, 0, 0, 0.6);
    color: #f2f2f7;
    margin: 12px;
    padding: 16px;
}

.balise-error-title {
    font-size: 13px;
    font-weight: 800;
    color: #ff6e6e;
}

.balise-error-text {
    color: #f2f2f7;
    font-size: 12px;
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
