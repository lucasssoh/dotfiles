import QtQuick
import "../theme"
import "../services"

// Native port of waybar's `memory` module. Sampling lives in the shared
// SystemStats singleton now -- see its header for why (one bar instance
// per monitor, memory usage is the same number on every screen).

Item {
    id: root

    // Fixed width, not Math.max(label.implicitWidth, ...) -- that
    // reactive form made the pill visibly grow/shrink as usedGB's digit
    // count changed. valueMetrics measures the worst-case string ONCE
    // with the real font instead.
    TextMetrics {
        id: valueMetrics
        font.family: Fonts.ui
        font.pixelSize: 13
        text: "199.9GB"
    }

    implicitWidth: iconGlyph.implicitWidth + label.spacing + valueMetrics.width + 20
    implicitHeight: 24

    Row {
        id: label
        anchors.centerIn: parent
        spacing: 4

        // Phosphor vs Inter: box-centering (anchors.verticalCenter) is
        // what measured aligned for Phosphor -- see Temperature.qml's
        // comment for the full reasoning/history.
        Text {
            id: iconGlyph
            renderType: Text.NativeRendering
            font.hintingPreference: Font.PreferNoHinting
            anchors.verticalCenter: parent.verticalCenter
            text: ""   // ph-memory
            color: SystemStats.memUsedPct >= 90 ? "#ff6e6e" : "#f2f2f7"
            font.family: Fonts.iconPhosphor
            font.pixelSize: 15
        }
        Text {
            id: valueLabel
            renderType: Text.NativeRendering
            font.hintingPreference: Font.PreferNoHinting
            anchors.verticalCenter: parent.verticalCenter
            // "G" -> "GB" (asked for, across all of METRICS: an
            // unambiguous unit rather than a bare letter).
            text: SystemStats.memUsedGB.toFixed(1) + "GB"
            color: SystemStats.memUsedPct >= 90 ? "#ff6e6e" : "#f2f2f7"
            font.family: Fonts.ui
            font.pixelSize: 13
        }
    }
}
