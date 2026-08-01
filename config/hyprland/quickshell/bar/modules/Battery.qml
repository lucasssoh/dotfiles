import QtQuick
import Quickshell.Services.UPower

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

    Text {
        id: label
        anchors.centerIn: parent
        text: root.present
            ? root.icon() + " " + Math.round(root.device.percentage) + "%"
            : ""
        // No critical/low-battery color in the original waybar/style.css
        // #battery rule -- always plain text, matched exactly here.
        color: "#f2f2f7"
        font.family: "JetBrains Mono"
        font.pixelSize: 13
    }
}
