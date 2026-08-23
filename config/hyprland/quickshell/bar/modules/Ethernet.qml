import QtQuick
import Quickshell.Io
import "../theme"

// Dedicated Ethernet module, asked for alongside Bluetooth/Network:
// "comme wifi et bt, gerer les etats on/off/connected... visuellement
// parlant avec les icones". Distinct from Network.qml's combined wifi/
// ethernet pill (that one stays as-is, showing whichever connection type
// is actually carrying traffic) -- this one only tracks the wired
// interface itself, mirroring Bluetooth.qml's on/off/connected shape.
//
// Status-only, no click action: neither Orbit (no dedicated wired --tab,
// its wired overlay is a side button inside the wifi tab) nor Balise
// (pre-cutover, not yet wired into the bar -- see the project plan) is
// the obvious click target yet. Revisit once one of them is.

Item {
    id: root

    // "off": no ethernet device on this machine at all.
    // "on": device present, but no cable / not the active connection.
    // "connected": device present and actively carrying an IP.
    property string state: "off"

    // Icon-only, same narrow floor as Bluetooth.qml/Network.qml.
    implicitWidth: Math.max(iconText.implicitWidth + 12, 24)
    implicitHeight: 24

    function poll() { if (!proc.running) proc.running = true; }

    Process {
        id: proc
        command: ["bash", "-c", `
line=$(nmcli -t -f DEVICE,TYPE,STATE device status 2>/dev/null | awk -F: '$2=="ethernet" {print; exit}')
if [ -z "$line" ]; then
    printf 'off'
elif [ "$(printf '%s' "$line" | cut -d: -f3)" = "connected" ]; then
    printf 'connected'
else
    printf 'on'
fi
`]
        stdout: StdioCollector {
            onStreamFinished: root.state = this.text.trim() || "off"
        }
    }

    // Event-driven like Network.qml's own watcher -- a persistent `nmcli
    // monitor` triggers a cheap one-shot re-query on any connectivity
    // change (cable plugged/unplugged, link up/down) instead of polling.
    Process {
        id: watcher
        command: ["nmcli", "monitor"]
        running: true
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: (line) => { if (line.trim() !== "" && !proc.running) proc.running = true; }
        }
    }

    Component.onCompleted: root.poll()

    // Point 4 (HIG "clarity": color carries state, not decoration) --
    // "off" (no wired device at all) is the genuinely inactive state,
    // same muted token Network.qml's "none" and Bluetooth.qml's
    // "poweredOff" already use. "on" (present, idle) stays full-bright,
    // same as Bluetooth's own "on".
    readonly property bool inactive: root.state === "off"

    // No literal "ethernet" glyph in Phosphor (checked against
    // phosphor-icons/core's codepoint metadata, same source balise-src/
    // src/ui/icon.rs used) -- ph-plugs-connected / ph-plugs, the same
    // pair Balise's own Ethernet tab uses.
    function icon() {
        if (root.state === "connected") return "";
        return "";
    }

    Text {
        id: iconText
        renderType: Text.NativeRendering
        font.hintingPreference: Font.PreferNoHinting
        anchors.centerIn: parent
        text: root.icon()
        color: root.inactive ? "#636366" : "#f2f2f7"
        font.family: Fonts.iconPhosphor
        font.pixelSize: 15
    }
}
