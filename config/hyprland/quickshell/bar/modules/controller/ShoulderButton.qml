import QtQuick
import QtQuick.Shapes
import "../../theme"

// A shoulder button (LB, L1, L…), shaped like the mock-up's: one outline,
// corners of 7 px on top and 10 px underneath, so it reads as a trigger cap
// rather than a pill.
Item {
    id: root

    property string label: ""

    anchors.verticalCenter: parent ? parent.verticalCenter : undefined
    width: Math.max(30, text.implicitWidth + 14)
    height: 22

    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            strokeColor: DrawerTheme.ink(0.28)
            strokeWidth: 1.2
            fillColor: "transparent"
            PathSvg {
                path: {
                    const w = root.width, h = root.height, e = 0.6, t = 7, b = 10;
                    return "M " + t + " " + e
                        + " L " + (w - t) + " " + e
                        + " A " + (t - e) + " " + (t - e) + " 0 0 1 " + (w - e) + " " + t
                        + " L " + (w - e) + " " + (h - b)
                        + " A " + (b - e) + " " + (b - e) + " 0 0 1 " + (w - b) + " " + (h - e)
                        + " L " + b + " " + (h - e)
                        + " A " + (b - e) + " " + (b - e) + " 0 0 1 " + e + " " + (h - b)
                        + " L " + e + " " + t
                        + " A " + (t - e) + " " + (t - e) + " 0 0 1 " + t + " " + e + " Z";
                }
            }
        }
    }
    Text {
        id: text
        anchors.centerIn: parent
        anchors.verticalCenterOffset: 0.5
        renderType: Text.NativeRendering
        text: root.label
        color: DrawerTheme.ink(0.78)
        font.family: Fonts.ui
        font.pixelSize: 10
        font.weight: Font.ExtraBold
    }
}
