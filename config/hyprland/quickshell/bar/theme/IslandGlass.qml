import QtQuick
import "../services"

// The central island's fill and inks, from IslandStyle (the user's
// ~/.config/hypr/bar.json; by default Graphite #2c2c2e at 20 %, no
// blur, dynamic text). In dynamic mode the TEXT turns light or dark,
// whichever holds best against the fill over what is behind it (bar-tint's
// profile), judged on the worst case -- the wallpaper's 10th and 90th
// percentile there as well as its mean. In static mode it is the file's
// `text` colour, always.
QtObject {
    id: glass

    property string monitor: ""
    property real rectX: 0
    property real rectW: 0

    readonly property color fill: Qt.rgba(IslandStyle.background.r, IslandStyle.background.g,
                                          IslandStyle.background.b, IslandStyle.alpha)
    readonly property color shadow: "transparent"

    // Dark text over a light stretch, light text otherwise, with a margin
    // so a wallpaper on the line does not flip it back and forth.
    property bool darkText: false
    readonly property real switchMargin: 1.0
    property real t: glass.darkText ? 1 : 0
    Behavior on t {
        NumberAnimation {
            duration: BandTint.transition
            easing.type: Easing.BezierSpline
            easing.bezierCurve: BandTint.transitionCurve
        }
    }

    readonly property color _light: "#f2f2f7"
    readonly property color _dark: "#1c1c1e"

    function reevaluate(): void {
        if (!glass.monitor || glass.rectW <= 0 || !BandTint.ready) return;
        const r = BandTint.rangeAt(glass.monitor, glass.rectX, glass.rectW);
        const mean = BandTint.backgroundAt(glass.monitor, glass.rectX, glass.rectW);
        if (!r || !mean) return;
        const over = [r.lo, r.hi, mean].map(c => BandTint.composite(glass.fill, c));
        const worst = ink => Math.min.apply(null, over.map(o => BandTint.contrast(ink, o)));
        const light = worst(glass._light), dark = worst(glass._dark);
        if (glass.darkText && light > dark + glass.switchMargin) glass.darkText = false;
        else if (!glass.darkText && dark > light + glass.switchMargin) glass.darkText = true;
    }
    onMonitorChanged: glass.reevaluate()
    onRectXChanged: { glass.reevaluate(); Qt.callLater(glass.bump); }
    onRectWChanged: { glass.reevaluate(); Qt.callLater(glass.bump); }
    Component.onCompleted: glass.reevaluate()
    readonly property int profileSeq: BandTint.seq
    onProfileSeqChanged: { glass.reevaluate(); glass.bump(); }
    // The fill is part of the surface the ink is judged on: a light/dark
    // switch or a new bar.json must re-decide, not wait for the wallpaper.
    property Connections styleChanges: Connections {
        target: IslandStyle
        function onBackgroundChanged() { glass.reevaluate(); glass.bump(); }
        function onAlphaChanged() { glass.reevaluate(); glass.bump(); }
        function onDynamicChanged() { glass.reevaluate(); glass.bump(); }
        function onTextColourChanged() { glass.reevaluate(); glass.bump(); }
    }

    // ---- per element ---------------------------------------------------
    // One ink for the whole island failed where the wallpaper changes
    // under it (a black trunk across a white sky): `at(item)` gives each
    // element -- the app name, the title, every workspace mark, the media
    // block -- the ink that holds best over what is right behind IT.
    // `revision` is what the bindings depend on; it moves when the
    // profile does or the island moves or resizes, once layout has run
    // (mapToItem is a call, not a binding).
    property int revision: 0
    function bump(): void { glass.revision++; }

    function at(item) {
        glass.revision;
        if (!IslandStyle.dynamic) return glass._staticSet;
        if (!item || !glass.monitor || !BandTint.ready) return glass._lightSet;
        const p = item.mapToItem(null, 0, 0);
        return glass._darkAt(p.x, Math.max(1, item.width)) ? glass._darkSet : glass._lightSet;
    }
    // A text that spans two grounds (a title across the trunk's edge)
    // cannot hold in one ink: `runs(item)` splits the item's width at the
    // profile's slices into runs of one ink each, in item coordinates, for
    // AdaptiveText to draw a clipped copy per run.
    function runs(item) {
        glass.revision;
        const w = item ? item.width : 0;
        if (!IslandStyle.dynamic) return [{ x0: 0, x1: Math.max(0, w), dark: false, fixed: true }];
        if (!item || w <= 0 || !glass.monitor || !BandTint.ready || !BandTint.profile[glass.monitor])
            return [{ x0: 0, x1: Math.max(0, w), dark: false }];
        const m = BandTint.profile[glass.monitor];
        const step = m.width / m.cells.length;
        const x = item.mapToItem(null, 0, 0).x;
        const out = [];
        let a = x;
        while (a < x + w) {
            const b = Math.min(x + w, (Math.floor(a / step) + 1) * step);
            const dark = glass._darkAt(a, Math.max(1, b - a));
            const last = out.length ? out[out.length - 1] : null;
            if (last && last.dark === dark) last.x1 = b - x;
            else out.push({ x0: a - x, x1: b - x, dark: dark });
            a = b;
        }
        return out;
    }
    function _darkAt(x, w) {
        const r = BandTint.rangeAt(glass.monitor, x, w);
        const mean = BandTint.backgroundAt(glass.monitor, x, w);
        if (!r || !mean) return false;
        const over = [r.lo, r.hi, mean].map(c => BandTint.composite(glass.fill, c));
        const worst = ink => Math.min.apply(null, over.map(o => BandTint.contrast(ink, o)));
        return worst(glass._dark) > worst(glass._light);
    }

    function mix(a, b) {
        return Qt.rgba(a.r + (b.r - a.r) * glass.t, a.g + (b.g - a.g) * glass.t,
                       a.b + (b.b - a.b) * glass.t, a.a + (b.a - a.a) * glass.t);
    }
    readonly property color _secondaryLight: "#c7c7cc"
    readonly property color _secondaryDark: "#3a3a3e"
    readonly property color _faintLight: "#8e8e93"
    readonly property color _faintDark: "#6e6e73"
    readonly property color _positiveLight: "#a3d9a5"
    readonly property color _positiveDark: "#24692a"

    // The inks, as the modules read them.
    readonly property color primary: glass.mix(glass._light, glass._dark)
    readonly property color secondary: glass.mix(glass._secondaryLight, glass._secondaryDark)
    readonly property color muted: glass.secondary
    readonly property color faint: glass.mix(glass._faintLight, glass._faintDark)
    readonly property color positive: glass.mix(glass._positiveLight, glass._positiveDark)
    readonly property color play: "#237823"

    readonly property var _lightSet: ({ primary: glass._light, secondary: glass._secondaryLight,
                                        muted: glass._secondaryLight, faint: glass._faintLight,
                                        positive: glass._positiveLight, play: glass.play })
    readonly property var _darkSet: ({ primary: glass._dark, secondary: glass._secondaryDark,
                                       muted: glass._secondaryDark, faint: glass._faintDark,
                                       positive: glass._positiveDark, play: glass.play })
    // Static mode: the file's text colour, its tiers as that colour fading.
    readonly property color _t: IslandStyle.textColour
    readonly property var _staticSet: ({ primary: glass._t,
                                         secondary: Qt.rgba(glass._t.r, glass._t.g, glass._t.b, 0.72),
                                         muted: Qt.rgba(glass._t.r, glass._t.g, glass._t.b, 0.72),
                                         faint: Qt.rgba(glass._t.r, glass._t.g, glass._t.b, 0.45),
                                         positive: glass._t, play: glass.play })
}
