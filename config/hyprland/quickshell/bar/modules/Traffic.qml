import QtQuick
import Quickshell
import Quickshell.Io
import "../theme"

// Split out of Network.qml (asked for): that module used to show BOTH
// the connection type (wifi/ethernet/none) AND the download rate in one
// TOOLS pill. Moved the rate half here, into METRICS, next to the other
// continuously-updating stats (Cpu/Temperature/Fan/Memory) -- Network.qml
// itself (still in TOOLS) goes back to a plain, stable connection-type
// icon, same "simple and stable" treatment Bluetooth.qml already got
// once its own battery % was dropped.
//
// Own interface-detection Process/Timer pair, not shared with
// Network.qml's -- this codebase doesn't have a cross-module state-
// sharing precedent for polled system data (every METRICS stat polls
// independently, see Cpu.qml/Memory.qml/etc.), so this follows the same
// convention rather than introducing a new one. Known minor cost: two
// `nmcli monitor` watchers instead of one, same category as the
// per-monitor duplicated Timer polling already flagged elsewhere in this
// bar -- not fixed here either.

Item {
    id: root

    property string iface: ""
    property string kind: "none"   // "wifi" | "ethernet" | "none"
    property real prevBytes: -1
    property real rateBps: 0

    implicitWidth: Math.max(label.implicitWidth + 20, 88)
    implicitHeight: 24

    Process {
        id: watcher
        command: ["nmcli", "monitor"]
        running: true
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: (line) => { if (line.trim() !== "" && !detect.running) detect.running = true; }
        }
    }

    Process {
        id: detect
        command: ["bash", "-c", `
e=$(nmcli -t -f DEVICE,TYPE,STATE dev status 2>/dev/null | awk -F: '$2=="ethernet" && $3=="connected" {print $1; exit}')
w=$(nmcli -t -f DEVICE,TYPE,STATE dev status 2>/dev/null | awk -F: '$2=="wifi" && $3=="connected" {print $1; exit}')
if [ -n "$e" ]; then
    printf '{"kind":"ethernet","iface":"%s"}' "$e"
elif [ -n "$w" ]; then
    printf '{"kind":"wifi","iface":"%s"}' "$w"
else
    printf '{"kind":"none","iface":""}'
fi
`]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const obj = JSON.parse(this.text.trim());
                    if (obj.iface !== root.iface) {
                        root.prevBytes = -1;   // new interface -> discard the old delta baseline
                        rxFile.path = obj.iface !== "" ? "/sys/class/net/" + obj.iface + "/statistics/rx_bytes" : "";
                    }
                    root.kind = obj.kind;
                    root.iface = obj.iface;
                } catch (e) {}
            }
        }
    }

    Component.onCompleted: detect.running = true

    FileView {
        id: rxFile
        blockLoading: true
    }

    function sample() {
        if (root.iface === "") { root.rateBps = 0; return; }
        rxFile.reload();
        const v = parseInt(rxFile.text().trim());
        if (isNaN(v)) return;
        if (root.prevBytes >= 0) root.rateBps = Math.max(0, (v - root.prevBytes) / 2);
        root.prevBytes = v;
    }

    Timer {
        interval: 2000
        running: true
        repeat: true
        onTriggered: root.sample()
    }

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
        // download side underneath (root.rateBps, rx_bytes only) -- the
        // glyph is about what this NUMBER represents (data moving),
        // not a claim that upload is being measured too.
        Text {
            renderType: Text.NativeRendering
            font.hintingPreference: Font.PreferNoHinting
            text: ""   // ph-arrows-down-up
            color: root.kind === "none" ? "#636366" : "#f2f2f7"
            font.family: Fonts.iconPhosphor
            font.pixelSize: 15
        }
        Text {
            renderType: Text.NativeRendering
            font.hintingPreference: Font.PreferNoHinting
            text: root.kind === "none" ? "----o/s" : root.formatRate(root.rateBps)
            color: root.kind === "none" ? "#636366" : "#f2f2f7"
            font.family: Fonts.ui
            font.pixelSize: 13
        }
    }
}
