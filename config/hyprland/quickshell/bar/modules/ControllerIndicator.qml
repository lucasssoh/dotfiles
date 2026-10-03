import QtQuick
import "../theme"
import "../services"

// A controller glyph at the head of the TOOLS row, next to "hdr", present
// only while a controller is connected. Same contract as HdrLabel.qml: an
// indicator, not a control, so presence is the whole signal and there is
// no "off" look. The battery follows the glyph when the pad reports one.
Item {
    id: root

    property QtObject ink: Ink
    property real trailingPad: 6

    visible: ControllerState.hasPad

    implicitWidth: row.implicitWidth + root.trailingPad
    implicitHeight: 24

    Row {
        id: row
        anchors.verticalCenter: parent.verticalCenter
        spacing: 4

        Text {
            anchors.verticalCenter: parent.verticalCenter
            renderType: Text.NativeRendering
            font.hintingPreference: Font.PreferNoHinting
            text: ""
            color: root.ink.primary
            font.family: Fonts.iconMingcute
            font.pixelSize: 15
        }
        Text {
            visible: ControllerState.battery !== null
            anchors.verticalCenter: parent.verticalCenter
            renderType: Text.NativeRendering
            font.hintingPreference: Font.PreferNoHinting
            text: ControllerState.battery + "%"
            // Red under 15 %, like the power dot: the one moment the
            // number asks for something.
            color: ControllerState.battery !== null && ControllerState.battery < 15 ? root.ink.danger : root.ink.primary
            font.family: Fonts.ui
            font.pixelSize: 13
            font.weight: Font.Medium
            font.features: { "tnum": 1 }
        }
    }
}
