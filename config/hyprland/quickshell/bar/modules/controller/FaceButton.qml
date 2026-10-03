import QtQuick
import QtQuick.Shapes
import "../../theme"

// One face button as the pad in hand prints it: a letter (Xbox, Switch,
// Steam), a PlayStation shape, or, for a pad nobody knows the labels of,
// four dots with its position lit. The cap stays neutral and only the
// symbol takes the button's colour, desaturated so it sits in the shell's
// greys. Drawn with Shapes: no image asset, sharp at any size.
Rectangle {
    id: cap

    // "letter" | "cross" | "circle" | "square" | "triangle" | "dots"
    property string kind: "letter"
    property string label: ""
    property color tint: DrawerTheme.primary
    // "n" | "e" | "s" | "w": which dot is lit for "dots".
    property string pos: "s"
    property real size: 24

    readonly property bool tinted: !Qt.colorEqual(cap.tint, DrawerTheme.primary)
    readonly property color ink: cap.kind === "dots" ? DrawerTheme.primary : cap.tint
    readonly property real u: cap.size / 24

    width: cap.size
    height: cap.size
    radius: cap.size / 2
    color: DrawerTheme.card
    border.width: Math.max(1.2, cap.size / 32)
    border.color: DrawerTheme.ink(cap.tinted ? 0.16 : 0.28)

    Text {
        visible: cap.kind === "letter"
        anchors.centerIn: parent
        renderType: Text.NativeRendering
        text: cap.label
        color: cap.ink
        font.family: Fonts.ui
        font.pixelSize: Math.round(cap.size * 0.48)
        font.weight: Font.ExtraBold
    }

    // The shapes take half the cap, as in the mock-up, drawn on a 24-unit
    // grid scaled to that half. The stroke stays heavy at small sizes so a
    // 24 px hint reads as firmly as the letters beside it.
    Shape {
        id: glyph
        visible: cap.kind !== "letter" && cap.kind !== "dots"
        readonly property real g: cap.size * (cap.size < 30 ? 0.56 : 0.48)
        readonly property real k: g / 24
        x: (cap.width - g) / 2
        y: (cap.height - g) / 2
        width: g
        height: g
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            strokeColor: cap.ink
            strokeWidth: Math.max(2, cap.size * 0.05)
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            joinStyle: ShapePath.RoundJoin

            PathSvg {
                path: {
                    const k = glyph.k;
                    const p = (x, y) => (x * k) + " " + (y * k);
                    switch (cap.kind) {
                    case "cross":
                        return "M " + p(5, 5) + " L " + p(19, 19) + " M " + p(19, 5) + " L " + p(5, 19);
                    case "square":
                        return "M " + p(4.5, 4.5) + " L " + p(19.5, 4.5) + " L " + p(19.5, 19.5) + " L " + p(4.5, 19.5) + " Z";
                    case "triangle":
                        return "M " + p(12, 3.5) + " L " + p(21, 19.5) + " L " + p(3, 19.5) + " Z";
                    case "circle":
                        return "M " + p(3.5, 12) + " A " + (8.5 * k) + " " + (8.5 * k) + " 0 1 1 " + p(20.5, 12)
                             + " A " + (8.5 * k) + " " + (8.5 * k) + " 0 1 1 " + p(3.5, 12);
                    }
                    return "";
                }
            }
        }
    }

    Repeater {
        model: cap.kind === "dots" ? [["n", 12, 5.5], ["w", 5.5, 12], ["e", 18.5, 12], ["s", 12, 18.5]] : []
        Rectangle {
            required property var modelData
            readonly property real d: 5.4 * cap.u
            x: modelData[1] * cap.u - d / 2
            y: modelData[2] * cap.u - d / 2
            width: d
            height: d
            radius: d / 2
            color: modelData[0] === cap.pos ? DrawerTheme.primary : DrawerTheme.ink(0.18)
        }
    }
}
