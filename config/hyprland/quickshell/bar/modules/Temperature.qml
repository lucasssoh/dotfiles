import QtQuick
import Quickshell.Io
import "../theme"

// Native port of waybar's `temperature` module. Timer + direct sysfs
// read via FileView, no subprocess. Same simplification as the original
// inline one-liner: hardcoded to thermal_zone0.

Item {
    id: root

    property int celsius: 0

    implicitWidth: Math.max(label.implicitWidth + 20, 52)   // 50 -> 52, point 6: 4pt grid
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

        // History on this Row's alignment: per-glyph size bumps, plain
        // top-alignment (Row's default), and anchors.baseline were each
        // right for a DIFFERENT icon font, not universally -- Nerd Font +
        // Inter happened to sit close enough at y:0; Font Awesome (drawn
        // like a letter, sitting ON the baseline) needed
        // anchors.baseline; Phosphor's glyphs are drawn floating,
        // vertically centered in their own line box rather than sitting
        // on the baseline -- box-centering (anchors.verticalCenter, both
        // items) is what actually measures aligned for THIS font, tested
        // pixel-precise against baseline-anchoring before picking it.
        // Moral: there's no one correct anchor mode across icon fonts,
        // has to be re-checked (screenshot, not assumed) per swap.
        Text {
            renderType: Text.NativeRendering
            font.hintingPreference: Font.PreferNoHinting
            anchors.verticalCenter: parent.verticalCenter
            text: ""   // ph-thermometer
            color: root.celsius >= 85 ? "#ff6e6e" : "#f2f2f7"
            font.family: Fonts.iconPhosphor
            font.pixelSize: 15
        }
        // waybar format: "{temperatureC:>3}" -- right-padded to 3 chars
        Text {
            id: valueLabel
            renderType: Text.NativeRendering
            font.hintingPreference: Font.PreferNoHinting
            anchors.verticalCenter: parent.verticalCenter
            text: String(root.celsius).padStart(3, " ")
            color: root.celsius >= 85 ? "#ff6e6e" : "#f2f2f7"
            font.family: Fonts.ui
            font.pixelSize: 13
        }
    }
}
