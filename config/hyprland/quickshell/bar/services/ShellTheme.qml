pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// The shell-wide look, from ~/.config/hypr/shell-theme.json:
//
//   { "style": "cartoon" }        default or cartoon
//
// `style` is the switch. The other keys are optional overrides:
//
//   { "style": "cartoon", "font": "Fredoka", "outline": 3,
//     "radius": 18, "accent": "#c9baf5" }
//
// Default keeps the shell exactly as it was. Cartoon is the inked,
// rounded, pastel look: thick outlines, hard offset shadows and a chunky
// font on every surface that reads DrawerTheme (drawers, OSD, toasts,
// notifications, controller, mixer, key sheet) plus the bar's own blocks.
//
// The file is watched: saving it changes the look without a restart, on a
// running shell. A missing or invalid file means default.
Singleton {
    id: root

    readonly property string configPath: Quickshell.env("HOME") + "/.config/hypr/shell-theme.json"

    property string style: "default"
    property string palette: "pastel"
    property string fontOverride: ""
    property real outlineOverride: 3
    property real radiusOverride: 18
    property string accentOverride: ""

    readonly property bool cartoon: root.style === "cartoon"
    readonly property string font: root.fontOverride || "Fredoka"
    readonly property real outline: root.cartoon ? Math.max(1, Math.min(6, root.outlineOverride)) : 0
    readonly property real radius: root.cartoon ? Math.max(12, Math.min(32, root.radiusOverride)) : 18

    readonly property color ink: "#000000"
    readonly property color outlineColour: "#000000"
    readonly property color shadowColour: "#000000"
    readonly property real shadowOffset: root.cartoon ? 5 : 0

    // Two colourways of the same cartoon structure. `pastel` is the
    // original lilac/lemon/mint set; `cuivre-cyan` follows the "3 touches"
    // mockup: neutral shells #292929, cards #3b3b3b, ink #f1eee6, with
    // copper #EDA16B and cyan #74CCD2 as the two loud touches.
    readonly property bool copperCyan: root.palette === "cuivre-cyan"

    readonly property color textPrimary: root.copperCyan ? "#f1eee6" : "#f7f3e6"
    readonly property color textSecondary: root.copperCyan ? "#c8c8c4" : "#d0ccd9"
    readonly property color textMuted: root.copperCyan ? "#a0a09c" : "#a5a2b0"
    readonly property color textFaint: root.copperCyan ? "#757570" : "#777482"

    readonly property color surfacePanel: root.copperCyan ? "#292929" : "#2e3140"
    readonly property color surfaceCard: root.copperCyan ? "#3b3b3b" : "#3a3e52"
    readonly property color surfaceCardHover: root.copperCyan ? "#474747" : "#454a60"
    readonly property color surfaceCardRaised: root.copperCyan ? "#505050" : "#484d64"
    readonly property color surfaceCardDeep: root.copperCyan ? "#1f1f1f" : "#21242f"

    // The pastels are shared by the palette and by the controller's face
    // buttons, so an accent override follows both.
    readonly property color accent: root.accentOverride
        || (root.copperCyan ? "#eda16b" : root.lilac)
    readonly property color lilac: root.copperCyan ? "#eda16b" : "#c9baf5"
    readonly property color lemon: root.copperCyan ? "#74ccd2" : "#e9f26b"
    readonly property color mint: root.copperCyan ? "#74ccd2" : "#9ce3ba"
    readonly property color salmon: root.copperCyan ? "#eda16b" : "#f5ada4"
    readonly property color sky: root.copperCyan ? "#74ccd2" : "#a9d7f5"
    readonly property color pink: root.copperCyan ? "#eda16b" : "#f3b8d8"
    // Two extra touches for the copper/cyan colourway: indigo for
    // display/night controls, sage for power/profile controls.
    readonly property color indigo: root.copperCyan ? "#8fa6dc" : "#a9d7f5"
    readonly property color sage: root.copperCyan ? "#a9c7a0" : "#9ce3ba"

    FileView {
        path: root.configPath
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: root.adopt(text())
        onLoadFailed: root.adopt("{}")
    }

    function adopt(raw) {
        var c;
        try {
            c = JSON.parse(raw) || {};
        } catch (e) {
            console.warn("[shell-theme] " + root.configPath + ": " + e);
            return;
        }
        if (!c || typeof c !== "object") return;
        root.style = c.style === "cartoon" ? "cartoon" : "default";
        root.palette = c.palette === "cuivre-cyan" ? "cuivre-cyan" : "pastel";
        root.fontOverride = typeof c.font === "string" ? c.font : "";
        root.outlineOverride = typeof c.outline === "number" ? c.outline : 3;
        root.radiusOverride = typeof c.radius === "number" ? c.radius : 18;
        root.accentOverride = typeof c.accent === "string" && /^#[0-9a-fA-F]{6}$/.test(c.accent)
            ? c.accent : "";
    }
}
