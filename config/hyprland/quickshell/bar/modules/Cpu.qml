import QtQuick
import "../theme"
import "../services"

// Native port of waybar's `cpu` module. Sampling now lives in the shared
// SystemStats singleton (services/SystemStats.qml) instead of this
// module polling /proc/stat itself -- see that file's header for why:
// this is one bar instance per monitor, and CPU usage is the same
// number on every screen, so one shared sample beats one per monitor.
//
// Text matches config.jsonc's format string for the usage half: "  {usage:>3}"
// -- right-padded to 3 chars, no "%" (waybar's own format string never
// had one, and asked to keep it that way for usage specifically). The
// frequency half DOES carry its unit ("GHz", asked for) -- highest
// per-core frequency across /proc/cpuinfo's "cpu MHz" lines, in GHz to
// 1 decimal.
//
// Width is a fixed constant, NOT Math.max(label.implicitWidth, ...) --
// that reactive form used to make the whole pill visibly grow/shrink
// every time usage crossed a digit boundary (9 -> 10, 99 -> 100) or the
// GHz decimal changed. valueMetrics below measures the actual worst-case
// string ONCE, with the real font, so the box is sized right without
// guessing a pixel number by hand -- same idea as Temperature.qml/
// Fan.qml/Memory.qml/Traffic.qml now do.

Item {
    id: root

    TextMetrics {
        id: valueMetrics
        font.family: Fonts.ui
        font.pixelSize: 13
        text: "100 9.9GHz"   // widest realistic usage+freq combo
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
            text: ""   // ph-cpu
            color: SystemStats.cpuUsage >= 90 ? "#ff6e6e" : "#f2f2f7"
            font.family: Fonts.iconPhosphor
            font.pixelSize: 15
        }
        Text {
            id: valueLabel
            renderType: Text.NativeRendering
            font.hintingPreference: Font.PreferNoHinting
            anchors.verticalCenter: parent.verticalCenter
            text: String(SystemStats.cpuUsage).padStart(3, " ") + " " + SystemStats.cpuMaxGhz.toFixed(1) + "GHz"
            color: SystemStats.cpuUsage >= 90 ? "#ff6e6e" : "#f2f2f7"
            font.family: Fonts.ui
            font.pixelSize: 13
        }
    }
}
