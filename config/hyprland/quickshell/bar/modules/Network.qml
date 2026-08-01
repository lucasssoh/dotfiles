import QtQuick
import Quickshell
import Quickshell.Io

// Native-ish ports of waybar's `network` module, but showing download
// throughput instead of the SSID/interface name (per request). Two
// different mechanisms combined:
//  - WHICH interface is active (wifi/ethernet/none): event-driven, a
//    persistent `nmcli monitor` watcher triggers a cheap one-shot
//    re-query only when connectivity actually changes -- same pattern
//    as the old network StreamModule.
//  - the actual byte-rate: structurally has to be a Timer (no kernel
//    event for "N bytes were transferred"), but zero subprocess -- a
//    delta between two direct /sys/class/net/<iface>/statistics/
//    rx_bytes reads via FileView, same category as Cpu.qml/Memory.qml.

Item {
    id: root

    property string iface: ""
    property string kind: "none"   // "wifi" | "ethernet" | "none"
    property int wifiSignal: 0     // 0-100, only meaningful when kind === "wifi"
    property real prevBytes: -1
    property real rateBps: 0

    // Widest realistic case: "  999.9M/s" -- rate string length swings a
    // lot more than the others (B/s -> K/s -> M/s), give it more room.
    implicitWidth: Math.max(label.implicitWidth + 20, 110)
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
    printf '{"kind":"ethernet","iface":"%s","signal":0}' "$e"
elif [ -n "$w" ]; then
    sig=$(nmcli -t -f IN-USE,SIGNAL dev wifi list ifname "$w" 2>/dev/null | awk -F: '$1=="*" {print $2; exit}')
    [ -z "$sig" ] && sig=0
    printf '{"kind":"wifi","iface":"%s","signal":%s}' "$w" "$sig"
else
    printf '{"kind":"none","iface":"","signal":0}'
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
                    root.wifiSignal = obj.signal || 0;
                } catch (e) {}
            }
        }
    }

    Component.onCompleted: detect.running = true

    // Signal strength drifts (moving around, interference) without
    // `nmcli monitor` necessarily firing a connectivity-change line --
    // this is a deliberate light poll (like cpu/temp/etc.), not free,
    // kept slow and only while actually on wifi.
    Timer {
        interval: 10000
        running: root.kind === "wifi"
        repeat: true
        onTriggered: if (!detect.running) detect.running = true
    }

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

    function formatRate(bps) {
        if (bps < 1024) return bps.toFixed(0) + "B/s";
        if (bps < 1024 * 1024) return (bps / 1024).toFixed(1) + "K/s";
        return (bps / 1024 / 1024).toFixed(1) + "M/s";
    }

    function icon() {
        if (root.kind === "ethernet") return "󰈀";
        if (root.kind === "wifi") {
            // waybar/config.jsonc's own 5-level format-icons array, same
            // weak -> strong order, picked by signal % instead of by
            // waybar's own internal signalStrength binding.
            const s = root.wifiSignal;
            if (s < 20) return "󰤯";
            if (s < 40) return "󰤟";
            if (s < 60) return "󰤢";
            if (s < 80) return "󰤥";
            return "󰤨";
        }
        return "󰤭";
    }

    Text {
        id: label
        anchors.centerIn: parent
        text: root.kind === "none" ? (root.icon() + "  ----o/s") : (root.icon() + "  " + root.formatRate(root.rateBps))
        color: "#f2f2f7"
        font.family: "JetBrains Mono"
        font.pixelSize: 13
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: (mouse) => {
            if (mouse.button === Qt.LeftButton)
                Quickshell.execDetached(["bash", "-c", "$HOME/.config/waybar/scripts/orbit-toggle.sh wifi"]);
            else
                Quickshell.execDetached(["wezterm", "start", "--class", "nm-tui-float", "--", "nmtui"]);
        }
    }
}
