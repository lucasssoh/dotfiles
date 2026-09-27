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
    visible: SystemStats.fanPath !== ""

    Row {
        id: row
        anchors.centerIn: parent
        spacing: 6

        StatReadout {
            value: String(SystemStats.fanRpm)
            widest: "9999"
            unit: "rpm"
            valueColor: root.ink.primary
            unitColor: root.ink.secondary
        }
    }
}
