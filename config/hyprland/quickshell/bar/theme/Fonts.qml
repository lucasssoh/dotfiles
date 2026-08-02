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
}
