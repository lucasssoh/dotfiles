import QtQuick
import "../../theme"
import "../../services"

// A pill at the bottom of the screen when a controller arrives: its name,
// how it is connected, and the hint that Guide opens the popup. Shown for
// three seconds by ControllerState; no history, nothing to dismiss.
Item {
    id: root

    readonly property var pad: ControllerState.banner
    property var last: null
    onPadChanged: if (pad) last = pad

    implicitWidth: pill.width
    implicitHeight: pill.height
    readonly property real pillOpacity: pill.opacity

    Rectangle {
        id: pill
        width: row.width + 20 + 18
        height: 48
        radius: height / 2
        color: DrawerTheme.panelTop
        border.width: 1
        border.color: DrawerTheme.ink(0.08)

        opacity: root.pad ? 1 : 0
        scale: root.pad ? 1 : 0.92
        Behavior on opacity { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
        Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

        Row {
            id: row
            x: 10
            anchors.verticalCenter: parent.verticalCenter
            spacing: 12

            Rectangle {
                width: 30
                height: 30
                radius: 15
                color: DrawerTheme.card
                Text {
                    anchors.centerIn: parent
                    renderType: Text.NativeRendering
                    text: ""
                    color: DrawerTheme.primary
                    font.family: Fonts.iconMingcute
                    font.pixelSize: 16
                }
            }
            Column {
                anchors.verticalCenter: parent.verticalCenter
                Text {
                    renderType: Text.NativeRendering
                    text: root.last ? root.last.name : ""
                    color: DrawerTheme.primary
                    font.family: Fonts.ui
                    font.pixelSize: 13
                    font.weight: Font.DemiBold
                }
                Text {
                    renderType: Text.NativeRendering
                    text: {
                        const p = root.last;
                        if (!p) return "";
                        const how = p.bus === "bluetooth" ? "Connected over Bluetooth" : p.bus === "usb" ? "Connected over USB" : "Connected";
                        const battery = p.battery !== null && p.battery !== undefined ? " · " + p.battery + " %" : "";
                        const opens = p.guide === false ? "Select + Start" : ControllerState._labels(p.family).guide;
                        return how + battery + " · " + opens + " opens the menu";
                    }
                    color: DrawerTheme.secondary
                    font.family: Fonts.ui
                    font.pixelSize: 11
                }
            }
        }
    }
}
