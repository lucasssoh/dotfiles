import QtQuick
import QtQuick.Shapes
import "../../theme"

// A controller silhouette that is its own battery gauge: a faint body,
// filled from the left as far as `level` goes, in the battery pill's state
// colours (the ink, green while charging, red under 15 %). With no level to
// show (a wired pad, or nothing reported yet) it is a plain outline.
Item {
    id: root

    // 0-100, or null for none.
    property var level: null
    property bool charging: false
    property QtObject ink: Ink

    implicitWidth: 22
    implicitHeight: 15

    readonly property bool known: root.level !== null && root.level !== undefined
    readonly property color fill: !root.known ? root.ink.primary
        : root.charging ? root.ink.positive
        : root.level < 15 ? root.ink.danger
        : root.ink.primary

    // The mock-up's outline, on a 24 x 16 grid.
    readonly property string outline: "M6.2 2h11.6a5 5 0 0 1 4.9 4.1l1 5.3a2.7 2.7 0 0 1-4.6 2.3"
        + "L16.7 11H7.3l-2.4 2.7a2.7 2.7 0 0 1-4.6-2.3l1-5.3A5 5 0 0 1 6.2 2z"

    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            scale: Qt.size(root.width / 24, root.height / 16)
            fillColor: root.known ? Qt.rgba(root.fill.r, root.fill.g, root.fill.b, 0.28) : "transparent"
            strokeColor: root.known ? "transparent" : root.ink.primary
            strokeWidth: root.known ? 0 : 1.6 * 24 / root.width
            PathSvg { path: root.outline }
        }
    }

    // The charge, clipped to its share of the width.
    Item {
        visible: root.known
        width: Math.round(root.width * Math.max(0, Math.min(100, root.level || 0)) / 100)
        height: root.height
        clip: true
        Shape {
            width: root.width
            height: root.height
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                scale: Qt.size(root.width / 24, root.height / 16)
                fillColor: root.fill
                strokeColor: "transparent"
                PathSvg { path: root.outline }
            }
        }
    }
}
