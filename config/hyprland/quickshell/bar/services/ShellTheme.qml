pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// The shell's look. ~/.config/hypr/shell-theme.json only selects:
//
//   { "style": "cartoon", "theme": "cuivre-cyan" }
//
// The theme itself is one JSON file in ~/.config/hypr/themes/, with one
// schema and both light and dark modes in the same file:
//
//   { "schema": "coucou-theme/1", "name": "Cuivre & Cyan",
//     "font": "Fredoka", "geometry": { "outline-width": 3 },
//     "modes": { "dark": { "surfaces": {...}, "text": {...},
//                          "accents": {...}, "outline": "#000000",
//                          "shadow": "#000000" },
//                "light": { ...same keys... } } }
//
// Every key is required. While the selected theme is missing or invalid,
// coucou.json stands in; if that one fails too, the shell keeps its default
// look rather than drawing cartoon shapes with made-up colours. The files
// are watched: saving one recolours the running shell.
Singleton {
    id: root

    readonly property string fallbackId: "coucou"
    readonly property string configPath: Quickshell.env("HOME") + "/.config/hypr/shell-theme.json"
    readonly property string themesDir: Quickshell.env("HOME") + "/.config/hypr/themes/"

    property string style: "default"
    property string themeId: root.fallbackId
    // Each file once parsed and validated, null when it is not. The
    // selected one stays watched while broken, so fixing it takes effect.
    property var selected: null
    property var fallback: null
    readonly property var theme: root.selected || root.fallback

    // The current mode's colours, null without a valid theme.
    readonly property var colours: root.theme
        ? root.theme.modes[AppearanceState.dark ? "dark" : "light"] : null
    readonly property bool cartoon: root.style === "cartoon" && root.colours !== null

    readonly property var schema: ({
        surfaces: ["panel", "card", "card-hover", "card-raised", "card-sunken"],
        text: ["primary", "secondary", "muted", "faint", "on-accent"],
        accents: ["active", "highlight", "success", "info", "warning", "danger"]
    })

    function isHex(v) {
        return typeof v === "string" && /^#[0-9a-fA-F]{6}$/.test(v);
    }

    function valid(t) {
        if (!t || t.schema !== "coucou-theme/1" || !t.modes) return false;
        for (const mode of ["dark", "light"]) {
            const m = t.modes[mode];
            if (!m || !isHex(m.outline) || !isHex(m.shadow)) return false;
            for (const group in root.schema) {
                if (!m[group]) return false;
                for (const key of root.schema[group])
                    if (!isHex(m[group][key])) return false;
            }
        }
        return true;
    }

    // One colour of the current mode. Black without a theme: the default
    // look never reads these, they only need to be a colour.
    function pick(group, key) {
        const g = root.colours ? (group ? root.colours[group] : root.colours) : null;
        return g ? g[key] : "#000000";
    }

    readonly property color ink: pick("text", "on-accent")
    readonly property color outlineColour: pick("", "outline")
    readonly property color shadowColour: pick("", "shadow")
    readonly property real shadowOffset: root.cartoon ? 5 : 0

    readonly property color textPrimary: pick("text", "primary")
    readonly property color textSecondary: pick("text", "secondary")
    readonly property color textMuted: pick("text", "muted")
    readonly property color textFaint: pick("text", "faint")

    readonly property color surfacePanel: pick("surfaces", "panel")
    readonly property color surfaceCard: pick("surfaces", "card")
    readonly property color surfaceCardHover: pick("surfaces", "card-hover")
    readonly property color surfaceCardRaised: pick("surfaces", "card-raised")
    readonly property color surfaceCardDeep: pick("surfaces", "card-sunken")

    readonly property color accent: pick("accents", "active")
    readonly property color highlight: pick("accents", "highlight")
    readonly property color success: pick("accents", "success")
    readonly property color info: pick("accents", "info")
    readonly property color warning: pick("accents", "warning")
    readonly property color danger: pick("accents", "danger")

    readonly property string font: root.theme && typeof root.theme.font === "string" ? root.theme.font : "Fredoka"
    readonly property var geometry: root.theme && root.theme.geometry ? root.theme.geometry : ({})
    readonly property real outline: root.cartoon
        ? Math.max(1, Math.min(6, typeof root.geometry["outline-width"] === "number" ? root.geometry["outline-width"] : 3)) : 0

    FileView {
        path: root.configPath
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: root.adopt(text())
        onLoadFailed: root.adopt("{}")
    }

    ThemeFile {
        path: root.themesDir + root.themeId + ".json"
        onParsed: t => root.selected = t
    }
    ThemeFile {
        path: root.themesDir + root.fallbackId + ".json"
        onParsed: t => root.fallback = t
    }

    component ThemeFile: FileView {
        signal parsed(var theme)
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onPathChanged: reload()
        onLoaded: {
            let t = null;
            try {
                t = JSON.parse(text());
            } catch (e) {
                // Mid-save or a typo: keep what is on screen until it parses.
                console.warn("[shell-theme] " + path + ": " + e);
                return;
            }
            if (!root.valid(t)) {
                console.warn("[shell-theme] invalid theme " + path);
                t = null;
            }
            parsed(t);
        }
        onLoadFailed: {
            console.warn("[shell-theme] cannot read " + path);
            parsed(null);
        }
    }

    function adopt(raw) {
        let c;
        try {
            c = JSON.parse(raw);
        } catch (e) {
            console.warn("[shell-theme] " + root.configPath + ": " + e);
            return;
        }
        if (!c || typeof c !== "object") c = {};
        root.style = c.style === "cartoon" ? "cartoon" : "default";
        root.themeId = typeof c.theme === "string" && /^[A-Za-z0-9_-]+$/.test(c.theme)
            ? c.theme : root.fallbackId;
    }
}
