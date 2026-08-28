import QtQuick
import Quickshell.Io
import Quickshell.Networking
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
//
// State used to come from a `nmcli monitor` watcher triggering a
// re-run `nmcli`/awk script on every change. Quickshell.Networking's
// WiredDevice.hasLink (cable present, DBus-pushed) and .connected
// (actively carrying an IP) replace both -- plain reactive binding,
// zero nmcli process.

Item {
    id: root

    // "off": no cable plugged in (WiredDevice.hasLink false), or no
    // ethernet device at all.
    // "on": cable plugged in (hasLink), nothing activated on it yet.
    // "connected": actively carrying an IP.
    // Best-across-all-wired-devices, not "first one found" -- a machine
    // can have more than one ethernet-type row (a real NIC plus e.g.
    // docker's veth), same reasoning the old nmcli version used.
    // "connected" beats "on" (cable in, idle) beats "off".
    readonly property string state: {
        const devices = Networking.devices.values;
        let hasLinkOnly = false;
        for (let i = 0; i < devices.length; i++) {
            const d = devices[i];
            if (d.type !== DeviceType.Wired) continue;
            if (d.connected) return "connected";
            if (d.hasLink) hasLinkOnly = true;
        }
        return hasLinkOnly ? "on" : "off";
    }

    // Icon-only, same narrow floor as Bluetooth.qml/Network.qml.
    implicitWidth: Math.max(iconText.implicitWidth + 12, 24)
    implicitHeight: 24

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
        font.pixelSize: 16
    }

    // No more onExited: root.poll() here -- state is DBus-pushed now, it
    // updates on its own as soon as NetworkManager reflects whatever
    // these did.
    Process {
        id: pickerProc
        command: ["bash", "-c", "$HOME/.config/waybar/scripts/balise-toggle.sh ethernet"]
    }

    Process {
        id: nmtuiProc
        command: ["wezterm", "start", "--class", "nm-tui-float", "--", "nmtui"]
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
