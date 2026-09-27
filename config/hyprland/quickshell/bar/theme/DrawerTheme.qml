pragma Singleton
import QtQuick

// The drawers' palette since the HyperOS pass: Ink's foreground names and
// Surfaces' background names in ONE object, each interpolated between a
// dark and a light material by `t`.
//
// Why a singleton of its own rather than Ink/Surfaces themselves: those
// two are read by the central island too (Workspaces, ActiveWindow, Veille,
// the keybinds sheet), which is black whatever is behind it and must stay
// dark. Everything that drops out of the BAND's islands -- Balise, power,
// mixer, notifications, the calendar, the launcher actions -- reads this
// instead, and so can follow the wallpaper the way the band's ink does
// (asked for as a test: "un mode light déclenché par le choix des
// wallpapers pour ces tiroirs, hormis le tiroir du centre").
//
// The names are exactly Ink's and Surfaces' (they share only `accent`),
// so moving a drawer onto this was a rename of the object, not of every
// property. What the values MEAN moved with the HyperOS pass:
//   - the surfaces are neutral greys, no longer the blue-grey
//     "graphite" (#14161d/#1a1d2a) that read as macOS;
//   - `accent` is no longer the platinum #a8b4c4 but simply the primary
//     ink: "on" is carried by inversion (see `on`/`onInk`), not by a tint;
//   - `on`/`onInk`/`onInk2` are new: the fill of an active control and
//     the two inks drawn on it -- the same inversion as the bar's active
//     workspace, and it flips with the material for free (light-on-dark
//     becomes dark-on-light).
QtObject {
    id: root

    // "auto" follows the wallpaper through `autoT`, which each bar keeps
    // pointed at the ink of whichever of its islands has a drawer open
    // (see shell.qml). "dark" and "light" pin it -- for testing, through
    // `qs -c bar ipc call bar setDrawerTheme light`.
    property string mode: "auto"
    property real autoT: 0
    readonly property real target: root.mode === "light" ? 1
                                  : root.mode === "dark" ? 0 : root.autoT
    // Its own Behavior so a pinned mode eases in too; `autoT` already
    // animates on IslandInk's 900ms, and this 250ms simply trails it.
    property real t: root.target
    Behavior on t { NumberAnimation { duration: 250; easing.type: Easing.InOutQuad } }

    // Endpoints are written as hex strings; Qt.tint against transparent is
    // the identity and turns them into colour values with .r/.g/.b/.a.
    function mix(a, b) {
        a = Qt.tint(a, "#00000000");
        b = Qt.tint(b, "#00000000");
        const k = root.t;
        return Qt.rgba(a.r + (b.r - a.r) * k, a.g + (b.g - a.g) * k,
                       a.b + (b.b - a.b) * k, a.a + (b.a - a.a) * k);
    }

    // ---- foreground (Ink's names) -------------------------------------
    readonly property color primary: mix("#f2f2f7", "#0c0c0e")
    readonly property color secondary: mix("#8e8e93", "#3a3a3e")
    readonly property color muted: mix("#636366", "#6e6e73")
    readonly property color faint: mix("#48484a", "#aeaeb2")
    readonly property color danger: mix("#ff6e6e", "#c4262e")
    readonly property color accent: root.primary
    readonly property color positive: mix("#a3d9a5", "#1f6b24")
    readonly property color play: mix("#237823", "#237823")
    readonly property color hdr: mix("#6be3e8", "#0b6d72")
    readonly property color onLight: mix("#0c0c0e", "#f2f2f7")

    // The primary ink at `alpha` -- what every `Qt.rgba(1, 1, 1, a)` in
    // the drawers became: a white veil on the dark material, a dark one
    // on the light material, same strength both ways.
    function ink(alpha) {
        const p = root.primary;
        return Qt.rgba(p.r, p.g, p.b, alpha);
    }

    // ---- the inversion ("on") -----------------------------------------
    readonly property color on: root.primary
    readonly property color onInk: root.onLight
    readonly property color onInk2: mix("#3a3a3e", "#c7c7cc")

    // ---- surfaces (Surfaces' names) -----------------------------------
    readonly property color panelTop: mix("#000000", "#ececef")
    readonly property color panelBottom: root.panelTop
    readonly property color card: mix("#17171a", "#ffffff")
    readonly property color cardHover: mix("#1f1f23", "#f6f6f8")
    readonly property color cardRaised: mix("#2a2a2f", "#e2e2e6")
    readonly property color cardDeep: mix("#0b0b0d", "#f4f4f6")
    readonly property color accentSoft: mix("#1c1c20", "#f1f1f4")
    readonly property color accentMedium: mix("#222226", "#ebebee")
    readonly property color accentStrong: mix("#2a2a2f", "#e2e2e6")
    readonly property color accentStrongest: mix("#323237", "#d8d8dc")
    readonly property color destructive: root.danger
    readonly property color destructiveSoft: mix("#2b1f22", "#fbe4e6")
    readonly property color destructiveSoftHover: mix("#3e262c", "#f6d2d6")
}
