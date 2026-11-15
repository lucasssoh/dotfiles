pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// The central island's look, from ~/.config/hypr/bar-island.json, the same
// kind of file as bar-position.json. Every key is optional; a missing file
// or key keeps the default.
//
//   {
//     "mode": "dynamic",        "dynamic": the text turns light or dark to
//                               suit what is behind each part of it.
//                               "static": the text is `text`, always.
//     "background": "#2c2c2e",  the island's colour
//     "opacity": 0.2,           0 (none) to 1 (opaque)
//     "blur": false,            blur what is behind the island
//     "text": "#f2f2f7"         static mode only: the text's colour
//   }
//
// Read live: saving the file changes the island at once, no restart.
Singleton {
    id: root

    readonly property string configPath: Quickshell.env("HOME") + "/.config/hypr/bar-island.json"

    readonly property bool defaultDynamic: true
    readonly property color defaultBackground: "#2c2c2e"
    readonly property real defaultOpacity: 0.20
    readonly property bool defaultBlur: false
    readonly property color defaultText: "#f2f2f7"

    property bool dynamic: root.defaultDynamic
    property color background: root.defaultBackground
    property real alpha: root.defaultOpacity
    property bool blur: root.defaultBlur
    property color textColour: root.defaultText

    FileView {
        path: root.configPath
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: root.adopt(text())
        onLoadFailed: root.adopt("{}")
    }

    function adopt(raw) {
        let c = {};
        try {
            c = JSON.parse(raw) || {};
        } catch (e) {
            // Mid-save or a typo: keep what is on screen until it parses.
            console.warn("[bar-island] " + root.configPath + ": " + e);
            return;
        }
        const isColour = v => typeof v === "string" && /^#([0-9a-fA-F]{6}|[0-9a-fA-F]{8})$/.test(v);
        root.dynamic = c.mode !== undefined ? c.mode !== "static" : root.defaultDynamic;
        root.background = isColour(c.background) ? c.background : root.defaultBackground;
        root.alpha = typeof c.opacity === "number" ? Math.max(0, Math.min(1, c.opacity)) : root.defaultOpacity;
        root.blur = typeof c.blur === "boolean" ? c.blur : root.defaultBlur;
        root.textColour = isColour(c.text) ? c.text : root.defaultText;
    }
}
