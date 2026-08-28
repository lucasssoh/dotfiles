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

    // Fixed width, not Math.max(label.implicitWidth, ...) -- that
    // reactive form made the pill visibly grow/shrink as the rate
    // string's length changed (B/s -> K/s -> M/s, digit count within
    // each). valueMetrics measures the worst-case string ONCE with the
    // real font instead.
    TextMetrics {
        id: valueMetrics
        font.family: Fonts.ui
        font.pixelSize: 13
        text: "999.9M/s"
    }

    implicitWidth: iconGlyph.implicitWidth + label.spacing + valueMetrics.width + 20
    implicitHeight: 24

    // One combined string here (unlike Network.qml's old two-row stack)
    // -- this sits among METRICS' other plain single-row stats (Cpu's
    // "  usage max_freq", Memory's "usedGB", etc.), so it follows their
    // shape instead of TOOLS' space-constrained stacked treatment.
    function formatRate(bps) {
        if (bps < 1024) return bps.toFixed(0) + "B/s";
        if (bps < 1024 * 1024) return (bps / 1024).toFixed(1) + "K/s";
        return (bps / 1024 / 1024).toFixed(1) + "M/s";
    }

    Row {
        id: label
        anchors.centerIn: parent
        spacing: 4

        // ph-arrows-down-up -- asked for specifically: a bidirectional
        // arrow reading as "traffic" rather than a connection-type
        // glyph (that's Network.qml's job now). Still really just the
        // download side underneath (SystemStats.netRateBps, rx_bytes
        // only) -- the glyph is about what this NUMBER represents (data
        // moving), not a claim that upload is being measured too.
        Text {
            id: iconGlyph
            renderType: Text.NativeRendering
            font.hintingPreference: Font.PreferNoHinting
            text: ""   // ph-arrows-down-up
            color: SystemStats.netKind === "none" ? "#636366" : "#f2f2f7"
            font.family: Fonts.iconPhosphor
            font.pixelSize: 15
        }
        Text {
            renderType: Text.NativeRendering
            font.hintingPreference: Font.PreferNoHinting
            text: SystemStats.netKind === "none" ? "----o/s" : root.formatRate(SystemStats.netRateBps)
            color: SystemStats.netKind === "none" ? "#636366" : "#f2f2f7"
            font.family: Fonts.ui
            font.pixelSize: 13
        }
    }
}
