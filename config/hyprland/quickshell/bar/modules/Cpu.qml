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

    // The ink ramp this module draws with. Points at the dark-material
    // singleton by default, which is what every call site below used
    // directly before this property existed -- so this changes nothing on
    // its own. It exists so the band's islands can hand a LIGHT ramp to
    // the modules sitting on them, per island, without touching any of
    // those call sites again. See theme/Ink.qml's MATERIAL note for why
    // the material flips rather than the ink alone.
    property QtObject ink: Ink

    // HyperOS pass: text only, no leading glyph -- see StatReadout.qml.
    // 6px a side, down from 10: without a glyph there is no icon/value
    // pair to give room to, just readings separated by that 12px.
    implicitWidth: row.implicitWidth + 12
    implicitHeight: 24

    Row {
        id: row
        anchors.centerIn: parent
        spacing: 6

        StatReadout {
            value: String(SystemStats.cpuUsage)
            widest: "100"
            unit: "%"
            valueColor: SystemStats.cpuUsage >= 90 ? root.ink.danger : root.ink.primary
            unitColor: root.ink.secondary
        }
        StatReadout {
            value: SystemStats.cpuMaxGhz.toFixed(1)
            widest: "9.9"
            unit: "GHz"
            valueColor: SystemStats.cpuUsage >= 90 ? root.ink.danger : root.ink.primary
            unitColor: root.ink.secondary
        }
    }
}
