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
    readonly property color primary: ShellTheme.cartoon
        ? (root.dark ? ShellTheme.textPrimary : "#1b1b22") : (root.dark ? "#f2f2f7" : "#1c1c1e")
    readonly property color secondary: ShellTheme.cartoon
        ? (root.dark ? ShellTheme.textSecondary : "#3c3b47")
        : (root.dark ? (root.glass ? "#a1a1a6" : "#8e8e93") : (root.glass ? "#3f3f44" : "#56565b"))
    readonly property color muted: ShellTheme.cartoon
        ? (root.dark ? ShellTheme.textMuted : "#5d5c69")
        : (root.dark ? (root.glass ? "#7c7c80" : "#636366") : (root.glass ? "#5e5e64" : "#86868b"))
    readonly property color faint: ShellTheme.cartoon
        ? (root.dark ? ShellTheme.textFaint : "#8c8a96")
        : (root.dark ? (root.glass ? "#5a5a5e" : "#48484a") : (root.glass ? "#9a9aa0" : "#c4c3be"))
    readonly property color danger: ShellTheme.cartoon ? ShellTheme.salmon : (root.dark ? "#ff6e6e" : "#b3261e")
    readonly property color accent: ShellTheme.cartoon ? ShellTheme.accent : root.primary
    readonly property color positive: ShellTheme.cartoon
        ? (ShellTheme.copperCyan ? ShellTheme.sage : ShellTheme.mint)
        : (root.dark ? "#a3d9a5" : "#24692a")
    readonly property color play: ShellTheme.cartoon
        ? (ShellTheme.copperCyan ? ShellTheme.sage : ShellTheme.mint) : "#237823"
    readonly property color hdr: ShellTheme.cartoon
        ? (ShellTheme.copperCyan ? ShellTheme.indigo : ShellTheme.sky)
        : (root.dark ? "#6be3e8" : "#006b75")
    // Amber for "the charger just dropped" and an eco low battery, and
    // the sky blue of charging under the conservation cap.
    readonly property color warning: ShellTheme.cartoon
        ? (ShellTheme.copperCyan ? ShellTheme.accent : ShellTheme.lemon)
        : (root.dark ? "#ffb454" : "#875000")
    readonly property color conserve: ShellTheme.cartoon
        ? (ShellTheme.copperCyan ? ShellTheme.sage : ShellTheme.lilac)
        : (root.dark ? "#8ecae6" : "#1d6386")
    readonly property color onLight: ShellTheme.cartoon ? ShellTheme.ink : (root.dark ? "#0c0c0e" : "#f7f5f0")

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
    readonly property color cream: ShellTheme.cartoon ? "#fdf8ef" : "#efece5"
    readonly property color cream2: ShellTheme.cartoon ? "#c6c2cf" : "#bdb9b0"
    function creamInk(alpha) {
        return Qt.rgba(root.cream.r, root.cream.g, root.cream.b, alpha);
    }

    // ---- the central island ------------------------------------------
    // What opens under the middle of the bar (Veille, Programme's alert,
    // the keybinds sheet) is a dark glass pane in both modes, so what it
    // reads from here is fixed: light inks, one step further from the
    // glass than they were from the black island, and veils for cards.
    readonly property color islandAccent: ShellTheme.cartoon
        ? (root.dark ? ShellTheme.textPrimary : "#1b1b22") : "#f2f2f7"
    readonly property color islandMuted: ShellTheme.cartoon
        ? (root.dark ? ShellTheme.textMuted : "#5d5c69") : "#8e8e93"
    readonly property color islandFaint: ShellTheme.cartoon
        ? (root.dark ? ShellTheme.textFaint : "#8c8a96") : "#6a6a6e"
    readonly property color islandCard: Qt.rgba(0.95, 0.95, 0.97, 0.08)
    readonly property color islandKey: Qt.rgba(0.95, 0.95, 0.97, 0.11)
    readonly property color islandCardRaised: Qt.rgba(0.95, 0.95, 0.97, 0.16)
    // The pane itself. In dark it is the drawers' own glass; in light the
    // blur behind is bright, so the veil thickens to keep the cream inks
    // readable.
    readonly property color islandPane: ShellTheme.cartoon
        ? (root.dark ? ShellTheme.surfacePanel : "#fdf8ef")
        : (root.dark ? root.glassPane : Qt.rgba(0.078, 0.078, 0.094, 0.72))
    // The edge of that pane, fixed dark like the rest of this palette:
    // the light-mode `paneRim` (white at 65%, the top light at 80%) drew
    // a glaring border around a dark pane ("une bordure blanche bizarre
    // qui n'est pas censé être là").
    readonly property color islandPaneRim: ShellTheme.cartoon ? ShellTheme.outlineColour : Qt.rgba(1, 1, 1, 0.14)
    readonly property color islandPaneHighlight: ShellTheme.cartoon ? "transparent" : Qt.rgba(1, 1, 1, 0.10)

    // ---- the inversion ("on") -----------------------------------------
    readonly property color on: ShellTheme.cartoon ? ShellTheme.accent : root.primary
    readonly property color onInk: ShellTheme.cartoon ? ShellTheme.ink : root.onLight
    readonly property color onInk2: ShellTheme.cartoon
        ? (root.dark ? ShellTheme.surfaceCardRaised : "#5d586b") : (root.dark ? "#3a3a3e" : "#c9c7c0")

    // ---- active, without the large white block (V3) --------------------
    // A large control that is on (a tile, a Balise row, a connected
    // network) no longer turns into a slab of `on`: it takes a stronger
    // veil and a fine edge, keeps the normal inks, and only the disc of
    // its icon inverts. Small things that are on (a segmented pill, a
    // chip, today in the calendar, a slider's fill) keep the full `on`.
    readonly property color activeFill: ShellTheme.cartoon
        ? ShellTheme.accent : (root.dark ? root.ink(0.15) : Qt.rgba(1, 1, 1, 0.85))
    readonly property color activeFillHover: ShellTheme.cartoon
        ? Qt.lighter(ShellTheme.accent, 1.06)
        : (root.dark ? root.ink(0.20) : Qt.rgba(1, 1, 1, 0.95))
    readonly property color activeEdge: ShellTheme.cartoon
        ? ShellTheme.outlineColour
        : (root.dark ? root.ink(0.22) : Qt.rgba(0.11, 0.11, 0.12, 0.10))
    readonly property color activeInk: ShellTheme.cartoon ? ShellTheme.ink : root.primary
    readonly property color activeInk2: ShellTheme.cartoon ? ShellTheme.surfaceCardRaised : root.secondary
    readonly property color activeDisc: ShellTheme.cartoon ? ShellTheme.ink : root.on
    readonly property color activeDiscInk: ShellTheme.cartoon ? ShellTheme.accent : root.onInk

    // ---- surfaces (Surfaces' names) -----------------------------------
    readonly property color panelTop: ShellTheme.cartoon
        ? (root.dark ? ShellTheme.surfacePanel : "#fdf8ef")
        : (root.dark ? "#000000" : "#f5f3ee")
    readonly property color panelBottom: root.panelTop
    // Glass cards (V3, "Aérien sans tasser"): a veil of the ink over the
    // glass rather than an opaque grey, so a card stands out by light and
    // the pane keeps the colour of what is behind it. Every surface that
    // reads these is itself glass (the drawers, OSD, alerts, Sesame, the
    // library, the side sheets), so a veil always has glass under it.
    // In light the veil is white: lighter than the warm grey glass, where
    // the opaque cards were lighter too.
    readonly property color card: ShellTheme.cartoon
        ? (root.dark ? ShellTheme.surfaceCard : "#ffffff") : (root.dark ? root.ink(0.08) : Qt.rgba(1, 1, 1, 0.46))
    readonly property color cardHover: ShellTheme.cartoon
        ? (root.dark ? ShellTheme.surfaceCardHover : "#f0eadb") : (root.dark ? root.ink(0.12) : Qt.rgba(1, 1, 1, 0.62))
    // On a card (an icon's disc, a track): a further step of the ink in
    // dark, a shade of black in light, as the opaque greys stepped.
    readonly property color cardRaised: ShellTheme.cartoon
        ? (root.dark ? ShellTheme.surfaceCardRaised : "#e7dfcd")
        : (root.dark ? root.ink(0.10) : Qt.rgba(0, 0, 0, 0.06))
    readonly property color cardDeep: ShellTheme.cartoon
        ? (root.dark ? ShellTheme.surfaceCardDeep : "#ded6c7")
        : (root.dark ? Qt.rgba(0, 0, 0, 0.18) : Qt.rgba(1, 1, 1, 0.30))
    readonly property color accentSoft: ShellTheme.cartoon
        ? (root.dark ? ShellTheme.surfaceCard : "#efe7f9") : (root.dark ? "#1c1c20" : "#e8e6e0")
    readonly property color accentMedium: ShellTheme.cartoon
        ? (root.dark ? ShellTheme.surfaceCardHover : "#e3d6f6") : (root.dark ? "#222226" : "#e1dfd8")
    readonly property color accentStrong: ShellTheme.cartoon
        ? (root.dark ? ShellTheme.surfaceCardRaised : ShellTheme.lilac) : (root.dark ? "#2a2a2f" : "#d9d7d0")
    readonly property color accentStrongest: ShellTheme.cartoon
        ? ShellTheme.lilac : (root.dark ? root.ink(0.16) : Qt.rgba(0, 0, 0, 0.12))
    readonly property color destructive: root.danger
    readonly property color destructiveSoft: ShellTheme.cartoon
        ? (root.dark ? "#3b2a30" : "#fbe0dc") : (root.dark ? "#2b1f22" : "#f5dedd")
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
    // Cartoon panes are opaque paper/ink: no blur region to ask Hyprland
    // for, and a hard outline instead of bright glass.
    readonly property bool glass: !ShellTheme.cartoon
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
    readonly property color paneRim: ShellTheme.cartoon ? ShellTheme.outlineColour : (root.dark ? Qt.rgba(1, 1, 1, 0.14) : Qt.rgba(1, 1, 1, 0.65))
    readonly property color paneHighlight: ShellTheme.cartoon ? "transparent" : (root.dark ? Qt.rgba(1, 1, 1, 0.10) : Qt.rgba(1, 1, 1, 0.80))
    // What the side sheets add over their glass towards the bottom, where
    // they are mostly empty: about 0.72 of glass in light, 0.55 in dark.
    readonly property color paneVeil: ShellTheme.cartoon
        ? root.clear(root.paneTop)
        : Qt.rgba(root.paneTop.r, root.paneTop.g, root.paneTop.b, root.dark ? 0.39 : 0.52)
    readonly property color paneShadow: ShellTheme.cartoon ? ShellTheme.shadowColour : (root.dark ? Qt.rgba(0, 0, 0, 0.30) : Qt.rgba(0, 0, 0, 0.16))
    readonly property color paneTop: root.glass ? root.glassPane : root.panelTop
    readonly property color paneBottom: root.glass ? root.glassPane : root.panelBottom
    readonly property color destructiveSoftHover: ShellTheme.cartoon
        ? (root.dark ? "#4c333b" : "#f7cfca") : (root.dark ? "#3e262c" : "#eecdcc")
}
