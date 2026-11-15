import QtQuick
import "../services"

// The central island's glass and inks, dark or light after the wallpaper
// behind the island (bar-tint's profile), not after the system's colour
// scheme: the drawers' light glass over a dark wallpaper stood out as a
// pale slab ("trop différent de ce qu'il y a derrière").
//
// The two ends are the drawers' own glass values (DrawerTheme with
// `glass`, dark and light), so the island still reads as the drawers'
// material; `t` eases between them over the wallpaper's own transition.
QtObject {
    id: glass

    property string monitor: ""
    property real rectX: 0
    property real rectW: 0

    // Dark glass below this luminance of the wallpaper behind the island,
    // light above, with a margin either side so a wallpaper sitting on
    // the line does not flip it back and forth.
    readonly property real threshold: 0.20
    readonly property real margin: 0.04
    property bool light: false
    property real t: glass.light ? 1 : 0
    Behavior on t {
        NumberAnimation {
            duration: BandTint.transition
            easing.type: Easing.BezierSpline
            easing.bezierCurve: BandTint.transitionCurve
        }
    }

    function reevaluate(): void {
        if (!glass.monitor || glass.rectW <= 0 || !BandTint.ready) return;
        const bg = BandTint.backgroundAt(glass.monitor, glass.rectX, glass.rectW);
        if (!bg) return;
        const l = BandTint.luminance(bg);
        if (glass.light && l < glass.threshold - glass.margin) glass.light = false;
        else if (!glass.light && l > glass.threshold + glass.margin) glass.light = true;
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

    // The glass (DrawerTheme.glassPane, paneRim, paneHighlight, paneShadow).
    readonly property color fill: glass.mix(Qt.rgba(0.078, 0.078, 0.094, 0.26), Qt.rgba(0.839, 0.827, 0.800, 0.42))
    readonly property color rim: glass.mix(Qt.rgba(1, 1, 1, 0.14), Qt.rgba(1, 1, 1, 0.65))
    readonly property color highlight: glass.mix(Qt.rgba(1, 1, 1, 0.10), Qt.rgba(1, 1, 1, 0.80))
    readonly property color shadow: glass.mix(Qt.rgba(0, 0, 0, 0.30), Qt.rgba(0, 0, 0, 0.16))

    // The inks on it (DrawerTheme's glass tiers), as the modules read them.
    // Ends as colour properties: mix() reads .r/.g/.b, which a string has not.
    readonly property color _primaryDark: "#f2f2f7"
    readonly property color _primaryLight: "#1c1c1e"
    readonly property color _secondaryDark: "#a1a1a6"
    readonly property color _secondaryLight: "#3f3f44"
    readonly property color _mutedDark: "#7c7c80"
    readonly property color _mutedLight: "#5e5e64"
    readonly property color _faintDark: "#5a5a5e"
    readonly property color _faintLight: "#9a9aa0"
    readonly property color _positiveDark: "#a3d9a5"
    readonly property color _positiveLight: "#24692a"
    readonly property color primary: glass.mix(glass._primaryDark, glass._primaryLight)
    readonly property color secondary: glass.mix(glass._secondaryDark, glass._secondaryLight)
    readonly property color muted: glass.mix(glass._mutedDark, glass._mutedLight)
    readonly property color faint: glass.mix(glass._faintDark, glass._faintLight)
    readonly property color positive: glass.mix(glass._positiveDark, glass._positiveLight)
    readonly property color play: "#237823"
}
