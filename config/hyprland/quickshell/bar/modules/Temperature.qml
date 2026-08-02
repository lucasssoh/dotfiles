import QtQuick
import Quickshell.Io
import "../theme"

// Native port of waybar's `temperature` module. Timer + direct sysfs
// read via FileView, no subprocess. Same simplification as the original
// inline one-liner: hardcoded to thermal_zone0.

Item {
    id: root

    property int celsius: 0

    implicitWidth: Math.max(label.implicitWidth + 20, 50)
    implicitHeight: 24

    FileView {
        id: tempFile
        path: "/sys/class/thermal/thermal_zone0/temp"
        blockLoading: true
    }

    function sample() {
        tempFile.reload();
        const raw = parseInt(tempFile.text().trim());
        root.celsius = isNaN(raw) ? 0 : Math.round(raw / 1000);
    }

    Timer {
        interval: 5000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.sample()
    }

    Row {
        id: label
        anchors.centerIn: parent
        spacing: 4

        Text {
            renderType: Text.NativeRendering
            font.hintingPreference: Font.PreferNoHinting
            text: "󰔏"
            color: root.celsius >= 85 ? "#ff6e6e" : "#f2f2f7"
            font.family: Fonts.icon
            font.pixelSize: 13
        }
        // waybar format: "{temperatureC:>3}" -- right-padded to 3 chars
        Text {
            renderType: Text.NativeRendering
            font.hintingPreference: Font.PreferNoHinting
            text: String(root.celsius).padStart(3, " ")
            color: root.celsius >= 85 ? "#ff6e6e" : "#f2f2f7"
            font.family: Fonts.ui
            font.pixelSize: 13
        }
    }
}
