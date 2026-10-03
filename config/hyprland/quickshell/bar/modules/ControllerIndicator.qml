import QtQuick
import "../theme"
import "../services"
import "controller"

// The connected controllers at the head of the TOOLS row, next to "hdr",
// present only while there is one. Same contract as HdrLabel.qml: an
// indicator, not a control, so presence is the signal and there is no
// "off" look. Each pad is a silhouette that doubles as its battery gauge
// (PadSilhouette.qml); two pads, two silhouettes.
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
        spacing: 3

        Repeater {
            model: ControllerState.pads
            PadSilhouette {
                required property var modelData
                anchors.verticalCenter: parent.verticalCenter
                ink: root.ink
                level: ControllerState.batteryOf(modelData)
                charging: modelData.charging
            }
        }
    }
}
