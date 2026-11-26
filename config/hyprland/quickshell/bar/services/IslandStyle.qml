pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// The bar's look, from ~/.config/hypr/bar.json (bar-island.json before it,
// still read when bar.json is missing). Every key is optional.
//
// Three independent levels:
//
//   {
//     "position": "top",          top or bottom (read by BarPosition)
//     "style": "solid",           solid: one bar. floating: band + blocks
//     "fill": {...},              the BAR's own surface
//     "text": {...},              the BAR's own text defaults
//     "light": {...}, "dark": {...},
//     "radius": 18,               one curve for windows, bar and screen
//     "center": {                 the centre zone, on top of the bar
//       "style": "flush",         flush, island, notch, dome or pill
//       "fill": {...}, "text": {...},
//       "light": {...}, "dark": {...}
//     },
//     "sides": {                  the left/right zone, on top of the bar
//       "style": "notch",         none, island, notch or pill
//       "fill": {...}, "text": {...},
//       "light": {...}, "dark": {...}
//     }
//   }
//
// The top level never becomes a zone's fill: a zone with no `fill` is
// transparent and shows the bar beneath it. Old flat configs, with no zone
// object, still get their fill on both zones as before.
//
// Read live by IslandStyle: the look needs no restart, though BarPosition
// restarts the bar on every save so the edge is re-read too.
Singleton {
    id: root

    readonly property string configPath: Quickshell.env("HOME") + "/.config/hypr/bar.json"
    readonly property string legacyPath: Quickshell.env("HOME") + "/.config/hypr/bar-island.json"

    // The raw file, kept so a light/dark switch re-resolves without a read.
    property var config: ({})
    property bool legacy: false
    readonly property bool darkMode: !AppearanceState.ready || AppearanceState.dark

    property bool solid: false
    // The two zones' own styles. Both are honoured in solid too: the side
    // shapes are drawn over the bar's surface.
    property string style: "island"         // the centre's shape
    property string sides: "none"           // the side blocks' shape

    // Level 1: the bar itself. `barFill` is also the band's material in
    // floating style (BandTint reads it), so the contrast maths follows
    // what is actually drawn.
    property color barBackground: "#000000"
    property real barAlpha: 1
    property bool barBlur: false
    property bool barDynamic: true
    property color barTextColour: "#f2f2f7"
    property color barFill: "#000000"

    // Level 2: the centre. The old names stay the centre's so existing
    // consumers (IslandGlass, the notch strip) keep the right surface.
    property bool dynamic: true
    property color background: "#2c2c2e"
    property real alpha: 0.20
    property bool blur: false
    property color textColour: "#f2f2f7"
    property color fill: "transparent"

    // Level 3: the side blocks. `sideFill` is what they really sit on:
    // their own shape when drawn, otherwise the bar's surface.
    property color sideBackground: "#000000"
    property real sideAlpha: 0
    property bool sideBlur: false
    property bool sideDynamic: true
    property color sideTextColour: "#f2f2f7"
    property color sideFill: "transparent"
    property color backdropFill: "transparent"
    readonly property bool sideVeil: !root.solid
    property real sideFillet: 18
    property bool _fillLightText: true

    // One radius for every curve: Hyprland's window rounding, the bar's
    // concave corners and fillets, the convex blocks and the screen corners
    // (the latter plus the gap windows keep from the edge). Small shapes
    // clamp it to half their height where they have to.
    property real radius: 18

    property real inset: 2
    property real innerInset: 2
    property real edgeRadius: 18
    property real innerRadius: 18
    property real fillet: 18
    // Solid style: the gap between the bar and the windows, and the radius
    // of the concave corners under it (the windows' own rounding).
    readonly property int gap: root.solid ? 6 : 0
    readonly property real cornerRadius: root.radius

    onDarkModeChanged: root.resolve()
    Connections {
        target: ShellTheme
        function onCartoonChanged() { Qt.callLater(root.resolve) }
        function onColoursChanged() { Qt.callLater(root.resolve) }
    }

    FileView {
        path: root.configPath
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: { root.legacy = false; root.adopt(text()); }
        onLoadFailed: { root.legacy = true; legacyFile.reload(); }
    }
    FileView {
        id: legacyFile
        path: root.legacyPath
        watchChanges: true
        printErrors: false
        onFileChanged: if (root.legacy) reload()
        onLoaded: if (root.legacy) root.adopt(text())
        onLoadFailed: if (root.legacy) root.adopt("{}")
    }

    function adopt(raw) {
        try {
            root.config = JSON.parse(raw) || {};
        } catch (e) {
            // Mid-save or a typo: keep what is on screen until it parses.
            console.warn("[bar] " + (root.legacy ? root.legacyPath : root.configPath) + ": " + e);
            return;
        }
        root.resolve();
    }

    function resolve() {
        const c = root.config || {};
        const obj = v => v && typeof v === "object" && !Array.isArray(v) ? v : {};
        const isColour = v => typeof v === "string" && /^#([0-9a-fA-F]{6}|[0-9a-fA-F]{8})$/.test(v);
        const isNumber = v => typeof v === "number" && isFinite(v);
        const between = (v, lo, hi) => Math.max(lo, Math.min(hi, v));
        const first = (...vs) => vs.find(v => v !== undefined);
        const modeKey = root.darkMode ? "dark" : "light";
        const topMode = obj(c[modeKey]);
        // Cartoon keeps the hierarchy of bar.json instead of flattening it:
        // the bar is paper, a zone that asks for its own fill takes the
        // palette's accent, and a zone with no fill stays transparent.
        // Position, style, zone shapes, radius, opacity and text mode all
        // still come from bar.json; only the palette changes. Default mode uses the colours as written.
        const cartoon = ShellTheme.cartoon;
        const paper = ShellTheme.surfacePanel;
        const paperInk = ShellTheme.textPrimary;
        const zonePaper = ShellTheme.surfaceCard;

        root.solid = c.style === "solid";

        const requestedRadius = first(c.radius, obj(c.shape).radius);
        if (requestedRadius !== undefined && !isNumber(requestedRadius))
            console.warn("[bar] radius must be a number");
        root.radius = isNumber(requestedRadius) ? between(requestedRadius, 0, 32) : 18;

        // A string is the old flat shape key; an object is a zone with its
        // own fill and text. `shape` and `style` are aliases inside a zone.
        const centerCfg = obj(c.center);
        const sidesCfg = obj(c.sides);
        const shape = obj(c.shape);
        const legacyCentre = first(
            typeof c.center === "string" ? c.center : undefined,
            typeof c.centre === "string" ? c.centre : undefined,
            typeof shape.style === "string" ? shape.style : undefined,
            typeof c.style === "string" && c.style !== "solid" && c.style !== "floating"
                ? c.style : undefined);

        const shapes = {
            island: { inset: 2, innerInset: 2, edge: root.radius, inner: root.radius, fillet: 0 },
            notch: { inset: 0, innerInset: 0, edge: 0, inner: root.radius, fillet: root.radius },
            dome: { inset: 0, innerInset: 0, edge: 0, inner: Math.max(18, root.radius), fillet: 0 },
            pill: { inset: 2, innerInset: 2, edge: 999, inner: 999, fillet: 0 },
            flush: { inset: 0, innerInset: 0, edge: 0, inner: 0, fillet: 0 }
        };
        const known = s => Object.prototype.hasOwnProperty.call(shapes, s);
        const centreShape = first(centerCfg.shape, centerCfg.style, legacyCentre);
        if (centreShape !== undefined && !known(centreShape))
            console.warn("[bar] unknown centre style " + centreShape);
        root.style = known(centreShape) ? centreShape : "island";
        const s = shapes[root.style];
        root.inset = s.inset;
        root.innerInset = s.innerInset;
        root.edgeRadius = s.edge;
        root.innerRadius = s.inner;
        root.fillet = s.fillet;

        const sideShapes = ["none", "island", "notch", "pill"];
        const sideShape = first(sidesCfg.shape, sidesCfg.style,
                                typeof c.sides === "string" ? c.sides : undefined);
        root.sides = sideShapes.indexOf(sideShape) >= 0 ? sideShape : "none";

        // ---- level 1: the bar ------------------------------------------
        const bf = Object.assign({}, obj(c.fill), obj(topMode.fill));
        const barColour = first(bf.colour, c.background);
        const barOpacity = first(bf.opacity, c.opacity);
        // Cartoon takes the band's colour from the theme (the drawers'
        // panel); its opacity and blur still come from bar.json.
        const barBg = cartoon ? paper
            : isColour(barColour) ? barColour
            : root.solid ? (root.darkMode ? "#000000" : "#f5f3ee") : "#0c0c0e";
        const barA = isNumber(barOpacity) ? between(barOpacity, 0, 1)
            : root.solid ? 1 : 0.45;
        const br = Qt.color(barBg);
        root.barBackground = barBg;
        root.barAlpha = barA;
        root.barFill = Qt.rgba(br.r, br.g, br.b, barA);
        const bBlur = first(bf.blur, c.blur);
        root.barBlur = typeof bBlur === "boolean" ? bBlur : false;
        const bt = Object.assign({}, obj(c.text), obj(topMode.text));
        root.barDynamic = !cartoon && first(bt.mode, c.mode, root.solid ? "static" : "dynamic") !== "static";
        root.barTextColour = cartoon ? paperInk
            : isColour(bt.colour) ? bt.colour
            : typeof c.text === "string" ? c.text
            : root.solid ? (root.darkMode ? "#f2f2f7" : "#1c1c1e") : "#f2f2f7";

        // ---- levels 2 and 3: the zones ---------------------------------
        // A zone with no object is the legacy zone: it still inherits the
        // flat fill. A real zone is transparent until it asks for a fill.
        function zone(cfg, defaultMode, role) {
            const legacyZone = Object.keys(cfg).length === 0;
            const zm = obj(cfg[modeKey]);
            const f = Object.assign({}, legacyZone ? obj(c.fill) : {},
                                    obj(cfg.fill),
                                    legacyZone ? obj(topMode.fill) : {},
                                    obj(zm.fill));
            const t = Object.assign({}, obj(c.text), obj(cfg.text),
                                    obj(topMode.text), obj(zm.text));
            const colour = first(f.colour, legacyZone ? c.background : undefined);
            const opacity = first(f.opacity, legacyZone ? c.opacity : undefined);
            const hasFill = isColour(colour);
            // Cartoon: the colours come from the theme, the shapes from
            // bar.json. The centre takes the accent, the sides the drawers'
            // panel, so a drawer reads as the bar opening up.
            const useCartoon = cartoon;
            const bg = useCartoon
                ? (legacyZone ? (root.solid ? zonePaper : paper)
                   : hasFill ? (role === "sides" ? paper : ShellTheme.accent) : "transparent")
                : hasFill ? colour
                : legacyZone ? (root.solid ? (root.darkMode ? "#000000" : "#f5f3ee") : "#2c2c2e")
                             : "#000000";
            const a = useCartoon
                ? (legacyZone || hasFill ? 1 : 0)
                : isNumber(opacity) ? between(opacity, 0, 1)
                : !legacyZone ? (hasFill ? 1 : 0)
                : root.solid ? 1 : 0.20;
            const rgb = Qt.color(bg);
            const lum = 0.2126 * rgb.r + 0.7152 * rgb.g + 0.0722 * rgb.b;
            // A translucent fill is mostly what is BEHIND it. Blend towards
            // mid-grey for the static fallback: black at 0 % must not ask
            // for white text on a white wallpaper.
            const chosen = first(t.colour, typeof c.text === "string" ? c.text : undefined);
            const ink = useCartoon
                ? (a < 0.05 ? paperInk
                   : (lum * a + 0.5 * (1 - a)) < 0.5 ? paperInk : ShellTheme.ink)
                : isColour(chosen) ? chosen
                : root.solid ? ((lum * a + 0.5 * (1 - a)) < 0.5 ? "#f2f2f7" : "#1c1c1e")
                             : "#f2f2f7";
            const b = first(f.blur, legacyZone ? c.blur : undefined);
            return {
                background: bg, alpha: a,
                blur: useCartoon ? false : typeof b === "boolean" ? b : false,
                // An opaque cartoon fill hides the wallpaper: its ink is fixed.
                dynamic: !useCartoon && first(t.mode, c.mode, defaultMode) !== "static",
                textColour: ink,
                fill: Qt.rgba(rgb.r, rgb.g, rgb.b, a)
            };
        }

        // The sides have always been contrast-driven; only the centre of a
        // solid bar defaults to static text.
        const centre = zone(centerCfg, root.solid ? "static" : "dynamic", "center");
        const side = zone(sidesCfg, "dynamic", "sides");

        // Source-over of a zone's fill on the bar beneath it. In solid
        // style the bar is opaque, so a transparent zone still has a real
        // surface under its text; the ink must judge that, not the wallpaper.
        function over(top, base) {
            const a = top.a;
            return Qt.rgba(a * top.r + (1 - a) * base.r,
                           a * top.g + (1 - a) * base.g,
                           a * top.b + (1 - a) * base.b, 1);
        }

        root.background = centre.background;
        root.alpha = centre.alpha;
        root.blur = centre.blur;
        root.dynamic = centre.dynamic;
        root.textColour = centre.textColour;
        root.fill = root.solid ? over(centre.fill, root.barFill) : centre.fill;
        const cr = Qt.color(centre.background);
        root._fillLightText = (0.2126 * cr.r + 0.7152 * cr.g + 0.0722 * cr.b) * centre.alpha
                              + 0.5 * (1 - centre.alpha) < 0.5;

        root.sideBackground = side.background;
        root.sideAlpha = side.alpha;
        root.sideBlur = side.blur;
        root.sideDynamic = side.dynamic;
        root.sideTextColour = side.textColour;
        // Side blocks sit on their own shape when one is drawn, otherwise
        // on the bar's surface (or just the band in a floating bar).
        root.sideFill = root.sides !== "none" ? side.fill
            : root.solid ? root.barFill : "transparent";
        root.backdropFill = root.solid ? root.barFill : root.sideFill;
        root.sideFillet = isNumber(sidesCfg.fillet) ? between(sidesCfg.fillet, 0, 32) : root.radius;
    }
}
