import QtQuick
import "../theme"
import "../services"

// Split out of Network.qml (asked for): that module used to show BOTH
// the connection type (wifi/ethernet/none) AND the download rate in one
// TOOLS pill. Moved the rate half here, into METRICS, next to the other
// continuously-updating stats (Cpu/Temperature/Fan/Memory) -- Network.qml
// itself (still in TOOLS) goes back to a plain, stable connection-type
// icon, same "simple and stable" treatment Bluetooth.qml already got
// once its own battery % was dropped.
//
// Interface detection + rate sampling now live in the shared SystemStats
// singleton -- see its header for why. This used to run its OWN `nmcli
// monitor` watcher and its own interface-detection Process, explicitly
// NOT shared with Network.qml's (see that module's separate detection),
// on the reasoning that this codebase had no cross-module state-sharing
// precedent for polled system data. That was true until SystemStats
// existed for Cpu/Memory/Temperature/Fan; once it did, folding Traffic's
// nmcli watcher in too was the same fix for the same reason: the bar is
// one instance PER MONITOR, so "own watcher, not shared" meant one
// `nmcli monitor` process and one detection script per screen, for the
// exact same interface/rate. Network.qml still runs its own separate
// detection for the connection-type icon -- not touched here, still a
// known (smaller) duplication, same category, just out of scope for
// this pass.

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

    // Value and unit split, so StatReadout can size and tint them apart.
    function rateValue(bps) {
        if (bps < 1024) return bps.toFixed(0);
        if (bps < 1024 * 1024) return (bps / 1024).toFixed(1);
        return (bps / 1024 / 1024).toFixed(1);
    }
    function rateUnit(bps) {
        if (bps < 1024) return "B/s";
        if (bps < 1024 * 1024) return "K/s";
        return "M/s";
    }

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
            readonly property bool offline: SystemStats.netKind === "none"
            value: offline ? "–" : root.rateValue(SystemStats.netRateBps)
            widest: "999.9"
            unit: offline ? "" : root.rateUnit(SystemStats.netRateBps)
            valueColor: offline ? root.ink.muted : root.ink.primary
        }
    }
}
