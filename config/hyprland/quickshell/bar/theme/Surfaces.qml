pragma Singleton
import QtQuick

// Surface palette for the drawer panels (Balise, the notification
// center). Asked for explicitly: "un style de type MacOs ou le bg est
// transparent ou translucide, mais les elements à l'interieur ne le sont
// pas, c'est ce que je voulais au debut mais quand il y a quelque chose
// derrière, impossible de faire la distinction".
//
// That is the whole rule this file encodes, and the reason it exists at
// all rather than the usual per-file hex literals this bar uses
// elsewhere: the panel and everything sitting on it have to be tuned
// TOGETHER (raise the panel's translucency and the cards must stay
// opaque, or the distinction the user lost the first time comes back),
// and that is impossible to keep straight when the values are spread
// across six files.
//
// There is no compositor blur behind any of this, deliberately -- the
// whole "glass" language in this bar is gradient + GlassRim, kept that
// way for battery (see DrawerIsland.qml/Osd.qml). So the panel alpha
// below is the readable end of macOS-style vibrancy rather than the
// heavily-blurred end: enough to read the wallpaper's colour through,
// not so much that text on it starts fighting the background.
QtObject {
    // ---- the panel itself: THE only translucent thing ----------------
    readonly property color panelTop: "#d91e2128"      // 85% of #1e2128
    readonly property color panelBottom: "#d9060608"   // 85% of #060608

    // ---- everything sitting ON the panel: fully opaque ---------------
    // Plain card/row fill and its hover, the two neutral tiers this bar
    // already used before any of this.
    readonly property color card: "#14161d"
    readonly property color cardHover: "#1a1d2a"
    // A step brighter again, for a control that needs to read as raised
    // against a card it sits on (the back button).
    readonly property color cardRaised: "#1f2330"

    readonly property color accent: "#a8b4c4"
    // Accent tints, PRE-BLENDED over `card` rather than written as
    // `Qt.rgba(accent, 0.14)` -- an alpha tint over a translucent panel
    // lets the wallpaper straight through the element, which is exactly
    // the failure being fixed. The percentages in the comments are what
    // each one used to be as an alpha.
    readonly property color accentSoft: "#262931"        // was 12%
    readonly property color accentMedium: "#292c34"      // was 14%
    readonly property color accentStrong: "#2f323b"      // was 18%
    readonly property color accentStrongest: "#353941"   // was 22%

    readonly property color destructive: "#ff6e6e"
    readonly property color destructiveSoft: "#2b1f25"       // was 10%
    readonly property color destructiveSoftHover: "#3e262c"  // was 18%
}
