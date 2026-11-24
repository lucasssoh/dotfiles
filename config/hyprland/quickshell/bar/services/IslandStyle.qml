pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// The central island's look, from ~/.config/hypr/bar-island.json, the same
// kind of file as bar-position.json. Every key is optional; a missing file
// or key keeps the default. The old flat keys (style, opacity, text...) are
// still read.
//
//   {
//     "shape": {
//       "style": "island",      island, notch, dome, pill or flush.
//                               Sets the other shape keys unless given.
//       "inset": 2,             px from the screen edge
//       "innerInset": 2,        px from the band-facing edge
//       "edgeRadius": 10,       px on the screen-edge corners
//       "innerRadius": 10,      px on the band-facing corners
//       "fillet": 0             notch: concave joint with the screen edge
//     },
//     "fill": {
//       "colour": "#2c2c2e",    the island's colour
//       "opacity": 0.2,         0 (none) to 1 (opaque)
//       "blur": false           blur what is behind the island
//     },
//     "text": {
//       "mode": "dynamic",      dynamic: follows what is behind it.
//                               static: always `colour`.
//       "colour": "#f2f2f7"
//     }
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
    readonly property string defaultStyle: "island"

    property bool dynamic: root.defaultDynamic
    property color background: root.defaultBackground
    property real alpha: root.defaultOpacity
    property bool blur: root.defaultBlur
    property color textColour: root.defaultText
    property string style: root.defaultStyle
    property real inset: 2
    property real innerInset: 2
    property real edgeRadius: 10
    property real innerRadius: 10
    property real fillet: 0

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
        const isNumber = v => typeof v === "number" && isFinite(v);
        const between = (v, lo, hi) => Math.max(lo, Math.min(hi, v));
        const shapes = {
            island: { inset: 2, innerInset: 2, edge: 10, inner: 10, fillet: 0 },
            notch: { inset: 0, innerInset: 0, edge: 0, inner: 10, fillet: 8 },
            dome: { inset: 0, innerInset: 0, edge: 0, inner: 18, fillet: 0 },
            pill: { inset: 2, innerInset: 2, edge: 999, inner: 999, fillet: 0 },
            flush: { inset: 0, innerInset: 0, edge: 0, inner: 0, fillet: 0 }
        };
        const obj = v => v && typeof v === "object" ? v : {};
        const sh = obj(c.shape), fi = obj(c.fill), tx = obj(c.text);
        const pick = (o, k, flat) => o[k] !== undefined ? o[k] : c[flat];
        const flatText = typeof c.text === "string" ? c.text : undefined;
        c = {
            style: pick(sh, "style", "style"),
            inset: pick(sh, "inset", "inset"),
            innerInset: pick(sh, "innerInset", "innerInset"),
            edgeRadius: pick(sh, "edgeRadius", "edgeRadius"),
            innerRadius: pick(sh, "innerRadius", "innerRadius"),
            fillet: pick(sh, "fillet", "fillet"),
            background: fi.colour !== undefined ? fi.colour : c.background,
            opacity: pick(fi, "opacity", "opacity"),
            blur: pick(fi, "blur", "blur"),
            mode: tx.mode !== undefined ? tx.mode : c.mode,
            text: tx.colour !== undefined ? tx.colour : flatText
        };
        const known = s => Object.prototype.hasOwnProperty.call(shapes, s);
        const shape = known(c.style) ? shapes[c.style] : shapes[root.defaultStyle];
        if (c.style !== undefined && !known(c.style))
            console.warn("[bar-island] " + root.configPath + ": unknown style " + c.style);
        root.dynamic = c.mode !== undefined ? c.mode !== "static" : root.defaultDynamic;
        root.background = isColour(c.background) ? c.background : root.defaultBackground;
        root.alpha = isNumber(c.opacity) ? between(c.opacity, 0, 1) : root.defaultOpacity;
        root.blur = typeof c.blur === "boolean" ? c.blur : root.defaultBlur;
        root.textColour = isColour(c.text) ? c.text : root.defaultText;
        root.style = known(c.style) ? c.style : root.defaultStyle;
        root.inset = isNumber(c.inset) ? between(c.inset, 0, 15) : shape.inset;
        root.innerInset = isNumber(c.innerInset) ? between(c.innerInset, 0, 15) : shape.innerInset;
        root.edgeRadius = isNumber(c.edgeRadius) ? between(c.edgeRadius, 0, 999) : shape.edge;
        root.innerRadius = isNumber(c.innerRadius) ? between(c.innerRadius, 0, 999) : shape.inner;
        root.fillet = isNumber(c.fillet) ? between(c.fillet, 0, 15) : shape.fillet;
    }
}
