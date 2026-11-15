import QtQuick
import "../services"

// One block's ink on the band: light or dark as BarInk decided for block
// `index`, eased over the wallpaper's own transition.
InkBlend {
    id: block

    property QtObject bar: null
    property int index: 0

    readonly property bool lightText: !block.bar || block.bar.lights[block.index] !== false
    t: block.lightText ? 0 : 1
    Behavior on t {
        NumberAnimation {
            duration: BandTint.transition
            easing.type: Easing.BezierSpline
            easing.bezierCurve: BandTint.transitionCurve
        }
    }
}
