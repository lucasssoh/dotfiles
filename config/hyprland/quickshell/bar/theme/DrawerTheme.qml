pragma Singleton
import QtQuick

// The drawers' palette since the HyperOS pass: Ink's foreground names and
// Surfaces' background names in ONE object, so a drawer reads a single
// source for everything it paints.
//
// Dark, permanently. A light material that followed the wallpaper through
// the band's inks was built and tried here, and dropped (asked for: "ne
// dynamise pas, garde en dark") -- the drawers sit over windows, and a
// panel that changes colour with the wallpaper behind the BAND read as
// arbitrary. What stayed from that pass is the vocabulary:
//   - the surfaces are neutral greys, no longer the blue-grey
//     "graphite" (#14161d/#1a1d2a) that read as macOS;
//   - `accent` is no longer the platinum #a8b4c4 but simply the primary
//     ink: "on" is carried by inversion (see `on`/`onInk`), not by a tint;
//   - `on`/`onInk`/`onInk2`: the fill of an active control and the two
//     inks drawn on it -- the same inversion as the bar's active
//     workspace.
//
// The names are exactly Ink's and Surfaces' (they share only `accent`),
// which is why moving a drawer onto this was a rename of the object, not
// of every property.
QtObject {
    id: root

    // ---- foreground (Ink's names) -------------------------------------
    readonly property color primary: "#f2f2f7"
    readonly property color secondary: "#8e8e93"
    readonly property color muted: "#636366"
    readonly property color faint: "#48484a"
    readonly property color danger: "#ff6e6e"
    readonly property color accent: root.primary
    readonly property color positive: "#a3d9a5"
    readonly property color play: "#237823"
    readonly property color hdr: "#6be3e8"
    readonly property color onLight: "#0c0c0e"

    // The primary ink at `alpha` -- what every `Qt.rgba(1, 1, 1, a)` in
    // the drawers became.
    function ink(alpha) {
        return Qt.rgba(root.primary.r, root.primary.g, root.primary.b, alpha);
    }

    // ---- the inversion ("on") -----------------------------------------
    readonly property color on: root.primary
    readonly property color onInk: root.onLight
    readonly property color onInk2: "#3a3a3e"

    // ---- surfaces (Surfaces' names) -----------------------------------
    readonly property color panelTop: "#000000"
    readonly property color panelBottom: root.panelTop
    readonly property color card: "#17171a"
    readonly property color cardHover: "#1f1f23"
    readonly property color cardRaised: "#2a2a2f"
    readonly property color cardDeep: "#0b0b0d"
    readonly property color accentSoft: "#1c1c20"
    readonly property color accentMedium: "#222226"
    readonly property color accentStrong: "#2a2a2f"
    readonly property color accentStrongest: "#323237"
    readonly property color destructive: root.danger
    readonly property color destructiveSoft: "#2b1f22"
    readonly property color destructiveSoftHover: "#3e262c"
}
