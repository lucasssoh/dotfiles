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
    // The three grey tiers sit one step further from the glass than from
    // the opaque panel: in dark, over a blurred white page the glass is a
    // mid grey, and #636366 on it
    // vanished (the calendar's weekdays, Power's history axis).
    readonly property color primary: root.dark ? "#f2f2f7" : "#1c1c1e"
    readonly property color secondary: root.dark ? (root.glass ? "#a1a1a6" : "#8e8e93") : (root.glass ? "#3f3f44" : "#56565b")
    readonly property color muted: root.dark ? (root.glass ? "#7c7c80" : "#636366") : (root.glass ? "#5e5e64" : "#86868b")
    readonly property color faint: root.dark ? (root.glass ? "#5a5a5e" : "#48484a") : (root.glass ? "#9a9aa0" : "#c4c3be")
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

    // `c` at zero alpha: the idle end of a fill or edge that eases in on
    // hover. Never "transparent" there -- that is transparent BLACK, and a
    // ColorAnimation from it runs through grey (a dark flash on the light
    // cream, a dull one on black).
    function clear(c) {
        return Qt.rgba(c.r, c.g, c.b, 0);
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
    // What opens under the middle of the bar (Veille, Programme's alert,
    // the keybinds sheet) is a dark glass pane in both modes, so what it
    // reads from here is fixed: light inks, one step further from the
    // glass than they were from the black island, and veils for cards.
    readonly property color islandAccent: "#f2f2f7"
    readonly property color islandMuted: "#8e8e93"
    readonly property color islandFaint: "#6a6a6e"
    readonly property color islandCard: Qt.rgba(0.95, 0.95, 0.97, 0.08)
    readonly property color islandKey: Qt.rgba(0.95, 0.95, 0.97, 0.11)
    readonly property color islandCardRaised: Qt.rgba(0.95, 0.95, 0.97, 0.16)
    // The pane itself. In dark it is the drawers' own glass; in light the
    // blur behind is bright, so the veil thickens to keep the cream inks
    // readable.
    readonly property color islandPane: root.dark ? root.glassPane : Qt.rgba(0.078, 0.078, 0.094, 0.72)
    // The edge of that pane, fixed dark like the rest of this palette:
    // the light-mode `paneRim` (white at 65%, the top light at 80%) drew
    // a glaring border around a dark pane ("une bordure blanche bizarre
    // qui n'est pas censé être là").
    readonly property color islandPaneRim: Qt.rgba(1, 1, 1, 0.14)
    readonly property color islandPaneHighlight: Qt.rgba(1, 1, 1, 0.10)

    // ---- the inversion ("on") -----------------------------------------
    readonly property color on: root.primary
    readonly property color onInk: root.onLight
    readonly property color onInk2: root.dark ? "#3a3a3e" : "#c9c7c0"

    // ---- active, without the large white block (V3) --------------------
    // A large control that is on (a tile, a Balise row, a connected
    // network) no longer turns into a slab of `on`: it takes a stronger
    // veil and a fine edge, keeps the normal inks, and only the disc of
    // its icon inverts. Small things that are on (a segmented pill, a
    // chip, today in the calendar, a slider's fill) keep the full `on`.
    readonly property color activeFill: root.dark ? root.ink(0.15) : Qt.rgba(1, 1, 1, 0.85)
    readonly property color activeFillHover: root.dark ? root.ink(0.20) : Qt.rgba(1, 1, 1, 0.95)
    readonly property color activeEdge: root.dark ? root.ink(0.22) : Qt.rgba(0.11, 0.11, 0.12, 0.10)
    readonly property color activeInk: root.primary
    readonly property color activeInk2: root.secondary
    readonly property color activeDisc: root.on
    readonly property color activeDiscInk: root.onInk

    // ---- surfaces (Surfaces' names) -----------------------------------
    readonly property color panelTop: root.dark ? "#000000" : "#f5f3ee"
    readonly property color panelBottom: root.panelTop
    // Glass cards (V3, "Aérien sans tasser"): a veil of the ink over the
    // glass rather than an opaque grey, so a card stands out by light and
    // the pane keeps the colour of what is behind it. Every surface that
    // reads these is itself glass (the drawers, OSD, alerts, Sesame, the
    // library, the side sheets), so a veil always has glass under it.
    // In light the veil is white: lighter than the warm grey glass, where
    // the opaque cards were lighter too.
    readonly property color card: root.dark ? root.ink(0.08) : Qt.rgba(1, 1, 1, 0.46)
    readonly property color cardHover: root.dark ? root.ink(0.12) : Qt.rgba(1, 1, 1, 0.62)
    // On a card (an icon's disc, a track): a further step of the ink in
    // dark, a shade of black in light, as the opaque greys stepped.
    readonly property color cardRaised: root.dark ? root.ink(0.10) : Qt.rgba(0, 0, 0, 0.06)
    readonly property color cardDeep: root.dark ? Qt.rgba(0, 0, 0, 0.18) : Qt.rgba(1, 1, 1, 0.30)
    readonly property color accentSoft: root.dark ? "#1c1c20" : "#e8e6e0"
    readonly property color accentMedium: root.dark ? "#222226" : "#e1dfd8"
    readonly property color accentStrong: root.dark ? "#2a2a2f" : "#d9d7d0"
    readonly property color accentStrongest: root.dark ? root.ink(0.16) : Qt.rgba(0, 0, 0, 0.12)
    readonly property color destructive: root.danger
    readonly property color destructiveSoft: root.dark ? "#2b1f22" : "#f5dedd"
    // ---- glass ---------------------------------------------------------
    // The split drawers' panes are glass: Hyprland blurs what is behind
    // them (the bar asks for it through ext-background-effect, see
    // shell.qml) and the pane itself is only a veil over it. Everything ON
    // the pane keeps its opaque card, which is what keeps it legible over
    // a white page as over a photo.
    //
    // Dark is "Vibrant": a 5% black veil, and the blur darkens what shows
    // through and pushes its colours, so the glass takes the colour of
    // what is behind. Light is "Brume": a warm grey veil over a blur that
    // no longer lightens. The cream "Lait" before it (50% veil, blur at
    // brightness 1.1) vanished over a white page and went flat milky grey
    // over a terminal; a veil darker than the page reads as a surface
    // everywhere, and the opaque cards on it stand out lighter than it.
    //
    // The blur's settings are global to Hyprland, so the bar pushes the
    // pair for the current mode whenever it flips (shell.qml, GLASS TONE).
    readonly property bool glass: true
    // Dark lifted in the V3 pass: at 0.38 the blur turned whatever was
    // behind into a near-black slab. 0.62 kept the colour but lost the
    // secondary inks over a white page (Power's axis, a tile's status);
    // 0.50 under a thicker veil (26%) keeps both, measured over a white
    // page and the wallpaper. Light stays "Brume": the lighter cream it replaced is
    // exactly what vanished over a white page.
    readonly property color glassPane: root.dark ? Qt.rgba(0.078, 0.078, 0.094, 0.26) : Qt.rgba(0.839, 0.827, 0.800, 0.42)
    readonly property real glassBrightness: root.dark ? 0.50 : 0.92
    readonly property real glassContrast: root.dark ? 0.92 : 0.82
    readonly property real glassVibrancy: root.dark ? 0.6 : 0.4
    readonly property real glassVibrancyDarkness: root.dark ? 0.2 : 0.0
    // The pane's edge (PaneEdge.qml) and the bar drawers' shadow, in
    // place of the convex lens: a hairline rim, a brighter line inside
    // the top, a soft shadow under.
    readonly property color paneRim: root.dark ? Qt.rgba(1, 1, 1, 0.14) : Qt.rgba(1, 1, 1, 0.65)
    readonly property color paneHighlight: root.dark ? Qt.rgba(1, 1, 1, 0.10) : Qt.rgba(1, 1, 1, 0.80)
    // What the side sheets add over their glass towards the bottom, where
    // they are mostly empty: about 0.72 of glass in light, 0.55 in dark.
    readonly property color paneVeil: Qt.rgba(root.paneTop.r, root.paneTop.g, root.paneTop.b, root.dark ? 0.39 : 0.52)
    readonly property color paneShadow: root.dark ? Qt.rgba(0, 0, 0, 0.30) : Qt.rgba(0, 0, 0, 0.16)
    readonly property color paneTop: root.glass ? root.glassPane : root.panelTop
    readonly property color paneBottom: root.glass ? root.glassPane : root.panelBottom
    readonly property color destructiveSoftHover: root.dark ? "#3e262c" : "#eecdcc"
}
