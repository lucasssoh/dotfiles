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

    implicitWidth: Math.max(label.implicitWidth + 20, 64)   // 65 -> 64, point 6: 4pt grid
    implicitHeight: 24
    visible: root.present

    // 10-tier Nerd Font array -> ph's own 5 tiers (full/high/medium/
    // low/empty) -- coarser, but ONE coherent glyph family, same
    // reasoning as Temperature/Fan/Bluetooth above.
    function icon() {
        const p = device.percentage || 0;
        if (p >= 87.5) return "";
        if (p >= 62.5) return "";
        if (p >= 37.5) return "";
        if (p >= 12.5) return "";
        return "";
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
            font.family: Fonts.iconPhosphor
            font.pixelSize: 14
        }
        Text {
            renderType: Text.NativeRendering
            font.hintingPreference: Font.PreferNoHinting
            text: root.present ? Math.round(root.device.percentage) + "%" : ""
            color: "#f2f2f7"
            font.family: Fonts.ui
            font.pixelSize: 12
        }
    }
}
