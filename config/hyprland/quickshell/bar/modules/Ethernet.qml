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
// Left click opens Balise on its Ethernet tab. This module shipped
// status-only at first, because back then neither Orbit (no dedicated
// wired tab) nor Balise (not yet wired into the bar) was an obvious
// click target; the cutover settled it.

Item {
    id: root

    // "off": no cable plugged in (NetworkManager's own "unavailable" --
    // no carrier), or no ethernet device/unmanaged at all.
    // "on": cable plugged in, device ready ("disconnected" -- NM's real
    // state once carrier is present but nothing's activated on it yet).
    // "connected": actively carrying an IP.
    property string state: "off"

    // Icon-only, same narrow floor as Bluetooth.qml/Network.qml.
    implicitWidth: Math.max(iconText.implicitWidth + 12, 24)
    implicitHeight: 24

    function poll() { if (!proc.running) proc.running = true; }

    Process {
        id: proc
        // Best-across-all-ethernet-devices, not "first line" -- a
        // machine can have more than one ethernet-type row (a real NIC
        // plus e.g. docker's veth/unmanaged interfaces), and nmcli's own
        // listing order isn't guaranteed to put the real NIC first.
        // "connected" beats "disconnected" (cable in, idle) beats
        // everything else (unavailable/unmanaged/absent -> "off").
        command: ["bash", "-c", `
lines=$(nmcli -t -f DEVICE,TYPE,STATE device status 2>/dev/null | awk -F: '$2=="ethernet"')
if printf '%s\\n' "$lines" | grep -q ':connected$'; then
    printf 'connected'
elif printf '%s\\n' "$lines" | grep -q ':disconnected$'; then
    printf 'on'
else
    printf 'off'
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

    // Same shape as Bluetooth.qml: a real Process with onExited re-polling,
    // so the icon updates as soon as the panel is done rather than waiting
    // for the next nmcli monitor event.
    Process {
        id: pickerProc
        command: ["bash", "-c", "$HOME/.config/waybar/scripts/balise-toggle.sh ethernet"]
        onExited: root.poll()
    }

    Process {
        id: nmtuiProc
        command: ["wezterm", "start", "--class", "nm-tui-float", "--", "nmtui"]
        onExited: root.poll()
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: (mouse) => {
            if (mouse.button === Qt.LeftButton) pickerProc.running = true;
            else nmtuiProc.running = true;
        }
    }
}
