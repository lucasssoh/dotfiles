pragma Singleton
import QtQuick

// Central font definitions for the whole bar -- change `ui` here and
// every module picks it up, instead of hunting through ~20 individual
// `font.family:` lines. Cross-referenced with (and kept in sync by hand
// with) config/theme/fonts.css, the real source of truth for Roue and
// Prisme -- QML can't @import a CSS file, so this is that value's
// Quickshell-side copy. See fonts.css's own header comment for the full
// picture across all 4 apps.
//
// `mono` is kept for any spot that genuinely needs fixed-width digits so
// fast-changing numbers don't jitter the layout -- currently unused
// (every module defaults to `ui`), opt back in per-module by swapping
// `font.family: Fonts.ui` for `font.family: Fonts.mono` where it
// actually matters.
//
// `icon` is the Nerd Font glyphs (battery/volume/network/cpu icons etc)
// render with -- those codepoints live in JetBrains Mono's own Nerd Font
// patch, not in Inter, so leaving `font.family: Fonts.ui` on a Text that
// mixes an icon glyph with real text left the icon's shape/weight up to
// whatever fontconfig happened to fall back to. Modules that mix an icon
// with a value now use two Text items side by side (Fonts.icon + Fonts.ui)
// instead of one Text with both in the same string, so each renders with
// the font actually meant for it.
QtObject {
    readonly property string ui: "Inter"
    readonly property string mono: "JetBrains Mono"
    readonly property string icon: "JetBrainsMono Nerd Font"

    // Font Awesome 6 Free/Brands -- first icon-font POC (still used for
    // `iconSolid`/`iconBrand` wherever nothing below has taken over yet).
    // `iconSolid` needs `font.weight: Font.Black` alongside it -- Font
    // Awesome 6 Free ships Regular (400, outline) and Solid (900, filled)
    // as the SAME family name, disambiguated by weight/style, not a
    // separate family string (verified via `fc-match`). `iconBrand` is a
    // genuinely separate family ("Font Awesome 6 Brands") -- product/
    // protocol logos (bluetooth, steam, discord) live there, not in Free.
    readonly property string iconSolid: "Font Awesome 6 Free"
    readonly property string iconBrand: "Font Awesome 6 Brands"

    // Phosphor -- second POC, now applied on Bluetooth/Temperature/Fan/
    // Battery in place of Font Awesome there (same root motivation: ONE
    // coherent family instead of Nerd Font's multi-project patchwork).
    // Tried instead of the real SF Symbols: Apple's own license
    // explicitly restricts SF Symbols to apps built FOR Apple platforms,
    // so it can't legally go in a Linux/Hyprland bar -- Phosphor is MIT-
    // licensed and, unlike Font Awesome, actually ships SF Symbols'
    // core idea: several DISTINCT weights of the same glyph set (thin/
    // light/regular/bold/fill/duotone) instead of a fixed
    // outline-or-filled split. Downloaded from the official
    // @phosphor-icons/web npm package (MIT, verified via its own
    // LICENSE file), installed to ~/.local/share/fonts.
    // Each weight is its OWN family/file (not one variable font with a
    // weight axis, unlike the Font Awesome Regular/Solid trick above) --
    // `fc-list` confirms this, so each needs its own `Fonts.` entry
    // rather than a shared name + `font.weight`. `iconPhosphor` is the
    // Regular weight specifically, chosen to track Inter's own default
    // (400) body weight -- the same "icon weight should track the type
    // weight next to it" idea SF Symbols itself is built around.
    readonly property string iconPhosphor: "Phosphor"

    // Bold weight, same "separate family per weight" deal as above --
    // confirmed via `fc-list` (Phosphor-Bold.ttf -> family "Phosphor-Bold",
    // not "Phosphor" + font.weight: Font.Bold, which does nothing on this
    // font). Opt-in per module, same as `mono` -- currently only the OSD
    // (Osd.qml), asked for specifically ("plus grand et plus gras").
    readonly property string iconPhosphorBold: "Phosphor-Bold"
}
