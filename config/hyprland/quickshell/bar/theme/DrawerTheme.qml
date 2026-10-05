pragma Singleton
import QtQuick
import "../services"

// The drawers' palette since the HyperOS pass: Ink's foreground names and
// Surfaces' background names in ONE object, so a drawer reads a single
// source for everything it paints.
//
// Dark or light, following AppearanceState.dark: the same desktop
// preference that flips GTK and the browser. Still not the wallpaper
// (asked for: "ne dynamise pas, garde en dark" -- a panel that changed
// colour with the wallpaper behind the BAND read as arbitrary); the light
// side is the same vocabulary inverted, on a light cream rather than pure
// white, with outlines doing the work of large white areas.
// What stayed from the HyperOS pass is the vocabulary:
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

    // Dark until the first read of the preference lands, so a drawer
    // opened during startup does not flash light for a frame.
    readonly property bool dark: !AppearanceState.ready || AppearanceState.dark

    // ---- foreground (Ink's names) -------------------------------------
    readonly property color primary: root.dark ? "#f2f2f7" : "#1c1c1e"
    readonly property color secondary: root.dark ? "#8e8e93" : "#56565b"
    readonly property color muted: root.dark ? "#636366" : "#86868b"
    readonly property color faint: root.dark ? "#48484a" : "#c4c3be"
    readonly property color danger: root.dark ? "#ff6e6e" : "#b3261e"
    readonly property color accent: root.primary
    readonly property color positive: root.dark ? "#a3d9a5" : "#24692a"
    readonly property color play: "#237823"
    readonly property color hdr: root.dark ? "#6be3e8" : "#006b75"
    // Amber for "the charger just dropped" and an eco low battery, and
    // the sky blue of charging under the conservation cap.
    readonly property color warning: root.dark ? "#ffb454" : "#875000"
    readonly property color conserve: root.dark ? "#8ecae6" : "#1d6386"
    readonly property color onLight: root.dark ? "#0c0c0e" : "#f7f5f0"

    // The primary ink at `alpha` -- what every `Qt.rgba(1, 1, 1, a)` in
    // the drawers became.
    function ink(alpha) {
        return Qt.rgba(root.primary.r, root.primary.g, root.primary.b, alpha);
    }

    // ---- cream (the central island's, fixed) --------------------------------------------------------
    // A slightly warm off-white for the two drawers that hang under the
    // central island at night, Veille and the keybinds sheet ("un léger
    // crème du blanc"). Softer than the #f2ecd9 / #c9c4b3 Veille wore
    // before the HyperOS pass, which read as yellow once set large
    // ("beaucoup trop intense"): a hint of warmth, not a colour. Kept off
    // every other drawer on purpose: it is the evening's ink, not a new
    // accent.
    readonly property color cream: "#efece5"
    readonly property color cream2: "#bdb9b0"
    function creamInk(alpha) {
        return Qt.rgba(root.cream.r, root.cream.g, root.cream.b, alpha);
    }

    // ---- the central island ------------------------------------------
    // The island (window title, workspaces, media, Veille, the keybinds
    // sheet) stays black in both modes, so what it reads from here is
    // fixed: the dark values, under their own names.
    readonly property color islandAccent: "#f2f2f7"
    readonly property color islandMuted: "#636366"
    readonly property color islandFaint: "#48484a"
    readonly property color islandCard: "#17171a"
    readonly property color islandCardRaised: "#2a2a2f"

    // ---- the inversion ("on") -----------------------------------------
    readonly property color on: root.primary
    readonly property color onInk: root.onLight
    readonly property color onInk2: root.dark ? "#3a3a3e" : "#c9c7c0"

    // ---- surfaces (Surfaces' names) -----------------------------------
    readonly property color panelTop: root.dark ? "#000000" : "#f5f3ee"
    readonly property color panelBottom: root.panelTop
    readonly property color card: root.dark ? "#17171a" : "#ebe9e3"
    readonly property color cardHover: root.dark ? "#1f1f23" : "#e3e1da"
    readonly property color cardRaised: root.dark ? "#2a2a2f" : "#dbd9d2"
    readonly property color cardDeep: root.dark ? "#0b0b0d" : "#efede8"
    readonly property color accentSoft: root.dark ? "#1c1c20" : "#e8e6e0"
    readonly property color accentMedium: root.dark ? "#222226" : "#e1dfd8"
    readonly property color accentStrong: root.dark ? "#2a2a2f" : "#d9d7d0"
    readonly property color accentStrongest: root.dark ? "#323237" : "#cfcdc6"
    // The two cards peeking under a collapsed notification stack, each a
    // step further from the front card.
    readonly property color stackMid: root.dark ? "#121215" : "#e4e2dc"
    readonly property color stackBack: root.dark ? "#0d0d10" : "#dddbd4"
    readonly property color destructive: root.danger
    readonly property color destructiveSoft: root.dark ? "#2b1f22" : "#f5dedd"
    readonly property color destructiveSoftHover: root.dark ? "#3e262c" : "#eecdcc"
}
