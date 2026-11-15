import QtQuick
import "../services"

// The central island's fill and inks: Graphite (#2c2c2e) at 20 %, no blur,
// chosen from a mockup ("graphite 20%"). The fill never changes; the TEXT
// does: light or dark, whichever holds best against the fill over what is
// behind the island (bar-tint's profile), judged on the worst case -- the
// wallpaper's 10th and 90th percentile there as well as its mean.
QtObject {
    id: glass

    property string monitor: ""
    property real rectX: 0
    property real rectW: 0

    readonly property color fill: Qt.rgba(0x2c / 255, 0x2c / 255, 0x2e / 255, 0.20)
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
    onRectXChanged: glass.reevaluate()
    onRectWChanged: glass.reevaluate()
    Component.onCompleted: glass.reevaluate()
    readonly property int profileSeq: BandTint.seq
    onProfileSeqChanged: glass.reevaluate()

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
}
