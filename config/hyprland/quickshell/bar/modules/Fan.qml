import QtQuick
import "../theme"
import "../services"

// Native port of waybar/scripts/fan.sh. hwmon discovery (the fan1_input
// glob) and sampling both live in the shared SystemStats singleton now
// -- see its header for why (one bar instance per monitor, fan RPM is
// the same number on every screen, and hwmonN's number isn't stable
// across machines so it only needs discovering once, not once per
// monitor).

Item {
    id: root

    // Fixed width, not Math.max(label.implicitWidth, ...) -- that
    // reactive form made the pill visibly grow/shrink as rpm's digit
    // count changed (or during the brief "N/A" at startup, before hwmon
    // discovery resolves). valueMetrics measures the worst-case string
    // ONCE with the real font instead. rpm is already padStart(4)'d.
    TextMetrics {
        id: valueMetrics
        font.family: Fonts.ui
        font.pixelSize: 13
        text: "9999"
    }

    implicitWidth: iconGlyph.implicitWidth + label.spacing + valueMetrics.width + 20
    implicitHeight: 24
    visible: SystemStats.fanPath !== ""

    Row {
        id: label
        anchors.centerIn: parent
        spacing: 4

        // Box-centering (anchors.verticalCenter) -- see Temperature.qml's
        // comment for the full history of why the right anchor mode
        // depends on the specific icon font, not a fixed rule.
        Text {
            id: iconGlyph
            renderType: Text.NativeRendering
            font.hintingPreference: Font.PreferNoHinting
            anchors.verticalCenter: parent.verticalCenter
            text: ""   // ph-fan
            color: "#f2f2f7"
            font.family: Fonts.iconPhosphor
            font.pixelSize: 15
        }
        Text {
            id: valueLabel
            renderType: Text.NativeRendering
            font.hintingPreference: Font.PreferNoHinting
            anchors.verticalCenter: parent.verticalCenter
            text: SystemStats.fanRpm
            color: "#f2f2f7"
            font.family: Fonts.ui
            font.pixelSize: 13
        }
    }
}
