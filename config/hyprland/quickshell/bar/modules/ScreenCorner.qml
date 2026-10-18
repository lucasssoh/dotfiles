import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Wayland

// One rounded corner of a screen: a black square with a quarter circle
// cut out, laid over the desktop so the panel reads with the silhouette
// of a phone's screen instead of a sharp rectangle.
//
// On the Top layer, like the bar, not Overlay: a fullscreen window covers
// it, so a video or a game shows its own corners and keeps direct scanout,
// with nothing to track. Drawn once and never repainted; it takes no
// input (empty mask), reserves no space and is not animated (no_anim in
// hypr/windowrules.lua).
PanelWindow {
    id: root

    // "topLeft", "topRight", "bottomLeft" or "bottomRight".
    required property string corner

    // Concentric with the windows: their rounding (12, hyprland.lua) plus
    // the gap they keep from the side and bottom edges (gaps_out 7 and 6),
    // so a window's curve and the screen's run parallel.
    readonly property int radius: 18

    readonly property bool atTop: corner === "topLeft" || corner === "topRight"
    readonly property bool atLeft: corner === "topLeft" || corner === "bottomLeft"

    anchors {
        top: root.atTop
        bottom: !root.atTop
        left: root.atLeft
        right: !root.atLeft
    }
    implicitWidth: root.radius
    implicitHeight: root.radius
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.namespace: "quickshell-corner"
    mask: Region { width: 0; height: 0 }
    color: "transparent"

    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer

        // Traced from the screen's own corner: along one edge, back along
        // the other, and the arc between them bulging towards that corner.
        ShapePath {
            readonly property real r: root.radius
            readonly property real cx: root.atLeft ? 0 : r
            readonly property real cy: root.atTop ? 0 : r
            fillColor: "black"
            strokeColor: "transparent"
            startX: cx
            startY: cy
            PathLine { x: root.atLeft ? root.radius : 0; y: root.atTop ? 0 : root.radius }
            PathArc {
                x: root.atLeft ? 0 : root.radius
                y: root.atTop ? root.radius : 0
                radiusX: root.radius
                radiusY: root.radius
                direction: (root.atLeft === root.atTop) ? PathArc.Counterclockwise : PathArc.Clockwise
            }
            PathLine { x: root.atLeft ? 0 : root.radius; y: root.atTop ? 0 : root.radius }
        }
    }
}
