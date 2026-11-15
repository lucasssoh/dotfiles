import QtQuick
import "../services"

// The central island's glass and inks: always the drawers' DARK glass and
// its light inks, whatever the system's scheme or the wallpaper. Only the
// glass's density moves, after the wallpaper behind the island (bar-tint's
// profile): the normal translucent glass over a calm stretch, a denser one
// over a busy or very bright one, where light text needs more under it.
//
// A light glass for light wallpapers was tried and dropped: switching
// between the two never kept step with the wallpaper's fade.
QtObject {
    id: glass

    property string monitor: ""
    property real rectX: 0
    property real rectW: 0

    // Busy or bright behind the island: the same texture threshold as the
    // band's (BandTint.textureStart), with a margin on the way back so a
    // wallpaper on the line does not flip it back and forth.
    property bool dense: false
    readonly property real brightLimit: 0.35
    property real t: glass.dense ? 1 : 0
    Behavior on t {
        NumberAnimation {
            duration: BandTint.transition
            easing.type: Easing.BezierSpline
            easing.bezierCurve: BandTint.transitionCurve
        }
    }

    function reevaluate(): void {
        if (!glass.monitor || glass.rectW <= 0 || !BandTint.ready) return;
        const r = BandTint.rangeAt(glass.monitor, glass.rectX, glass.rectW);
        if (!r) return;
        const bright = BandTint.luminance(r.hi);
        if (glass.dense)
            glass.dense = r.texture >= BandTint.textureStart - 3 || bright > glass.brightLimit - 0.05;
        else
            glass.dense = r.texture >= BandTint.textureStart || bright > glass.brightLimit;
    }
    onMonitorChanged: glass.reevaluate()
    onRectXChanged: glass.reevaluate()
    onRectWChanged: glass.reevaluate()
    Component.onCompleted: glass.reevaluate()
    readonly property int profileSeq: BandTint.seq
    onProfileSeqChanged: glass.reevaluate()

    // The glass: DrawerTheme's dark glassPane (26 %), up to 55 % when dense.
    readonly property color fill: Qt.rgba(0.078, 0.078, 0.094, 0.26 + (0.55 - 0.26) * glass.t)
    readonly property color shadow: Qt.rgba(0, 0, 0, 0.30)

    // The inks on it: DrawerTheme's dark glass tiers.
    readonly property color primary: "#f2f2f7"
    readonly property color secondary: "#a1a1a6"
    readonly property color muted: "#7c7c80"
    readonly property color faint: "#5a5a5e"
    readonly property color positive: "#a3d9a5"
    readonly property color play: "#237823"
}
