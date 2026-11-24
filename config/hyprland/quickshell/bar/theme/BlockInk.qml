import QtQuick
import "../services"

// One block's light or dark ink, eased over the wallpaper transition.
// BarInk decides it from bar-tint's profile, with the bar's own fill
// composited over that profile.
InkBlend {
    id: block

    property QtObject bar: null
    property int index: 0

    // The sides' own text block from bar.json. In dynamic mode the ramp
    // still comes from BarInk's per-block contrast decision; in static mode
    // every tier is a fade of `sides.text.colour`.
    useStatic: !IslandStyle.sideDynamic
    staticInk: IslandStyle.sideTextColour

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
