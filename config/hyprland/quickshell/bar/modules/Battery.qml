import QtQuick
import Quickshell.Services.UPower
import "../theme"

// Native port of waybar's `battery` module. Zero exec, zero poll:
// UPower.displayDevice is DBus-signal-backed. Collapses to nothing on
// desktops with no battery (isLaptopBattery false / not present) --
// same graceful-degradation intent as the old shell one-liner had.

Item {
    id: root

    readonly property var device: UPower.displayDevice
    readonly property bool present: device && device.isLaptopBattery && device.ready

    implicitWidth: Math.max(label.implicitWidth + 20, 65)
    implicitHeight: 24
    visible: root.present

    function icon() {
        const p = Math.floor((device.percentage || 0) / 10);
        const icons = ["󰁺", "󰁻", "󰁼", "󰁽", "󰁾", "󰁿", "󰂀", "󰂁", "󰂂", "󰁹"];
        return icons[Math.min(p, 9)];
    }

    // No critical/low-battery color in the original waybar/style.css
    // #battery rule -- always plain text, matched exactly here.
    Row {
        id: label
        anchors.centerIn: parent
        spacing: 4
        visible: root.present

        Text {
            renderType: Text.NativeRendering
            font.hintingPreference: Font.PreferNoHinting
            text: root.present ? root.icon() : ""
            color: "#f2f2f7"
            font.family: Fonts.icon
            font.pixelSize: 13
        }
        Text {
            renderType: Text.NativeRendering
            font.hintingPreference: Font.PreferNoHinting
            text: root.present ? Math.round(root.device.percentage) + "%" : ""
            color: "#f2f2f7"
            font.family: Fonts.ui
            font.pixelSize: 13
        }
    }
}
