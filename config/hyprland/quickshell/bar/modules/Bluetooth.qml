import QtQuick
import Quickshell.Io
import Quickshell.Bluetooth
import "../theme"

// Native-ish port of waybar's `bluetooth` module. Used to poll --
// bluetoothctl's own output has no clean push source, so this ran a
// Timer (45s, then 8s once that proved too slow) forking `bash -c
// "bluetoothctl show | awk ...; bluetoothctl devices Connected | awk
// ..."` on every tick, plus the two actions that actually change
// bluetooth state (balise's picker, blueman-manager) forced an extra
// re-poll on exit just to feel current sooner.
//
// Quickshell.Bluetooth wraps BlueZ's own DBus objects directly (same
// family as Battery.qml's UPower and AudioOutput/AudioInput's Pipewire)
// -- Bluetooth.defaultAdapter.enabled and each device's .connected are
// bindable/notify-backed, pushed by BlueZ the instant it changes. Zero
// forks, zero polling interval to tune, and state now updates BEFORE
// the picker/manager process even exits, not after.
//
// Icon-only, no battery % (asked for, to save space) -- was showing
// BlueZ's connected-device battery reading next to the glyph (still
// available for free via BluetoothDevice.battery if that comes back).

Item {
    id: root

    // No BluetoothAdapter until BlueZ actually reports one (radio
    // present + service up) -- treat that transient "not there yet" the
    // same as "off" rather than a 4th state to design for.
    readonly property bool adapterEnabled: Bluetooth.defaultAdapter !== null && Bluetooth.defaultAdapter.enabled
    readonly property bool anyDeviceConnected: {
        if (!Bluetooth.defaultAdapter) return false;
        const devices = Bluetooth.defaultAdapter.devices.values;
        for (let i = 0; i < devices.length; i++) {
            if (devices[i].connected) return true;
        }
        return false;
    }
    readonly property string state: !adapterEnabled ? "off" : (anyDeviceConnected ? "connected" : "on")   // "off" | "on" | "connected"

    // Icon-only now (battery % dropped -- asked for, to save space):
    // same narrow floor as Performance.qml's own icon-only module.
    implicitWidth: Math.max(iconText.implicitWidth + 12, 24)
    implicitHeight: 24

    // Point 4 (HIG "clarity": color carries state, not decoration) --
    // radio powered OFF is the one state here that's genuinely inactive
    // (vs. "on but nothing connected", which is still available/
    // actionable and stays full-bright). Same muted token Network.qml's
    // own "none" state now uses.
    readonly property bool poweredOff: root.state === "off"

    // Phosphor actually ships distinct glyphs per state here (checked
    // after being asked, not assumed the first time around) --
    // ph-bluetooth-slash / ph-bluetooth / ph-bluetooth-connected. Back to
    // real shape-per-state (like the old Nerd Font version had), on top
    // of the color distinction, rather than one shape doing all the work.
    function icon() {
        if (root.state === "off") return "";
        if (root.state === "connected") return "";
        return "";
    }

    // Point 4 (HIG "clarity") still applies to color on top of the shape
    // change -- off stays muted, matching Network.qml's own "none" token.
    Text {
        id: iconText
        renderType: Text.NativeRendering
        font.hintingPreference: Font.PreferNoHinting
        anchors.centerIn: parent
        text: root.icon()
        color: root.poweredOff ? "#636366" : "#f2f2f7"
        font.family: Fonts.iconPhosphor
        font.pixelSize: 16
    }

    // No more onExited: root.poll() here -- state is DBus-pushed now,
    // it updates on its own as soon as BlueZ reflects whatever these
    // did, no need to force a re-check when the process closes.
    Process {
        id: pickerProc
        command: ["bash", "-c", "$HOME/.config/waybar/scripts/balise-toggle.sh bluetooth"]
    }

    Process {
        id: managerProc
        command: ["blueman-manager"]
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: (mouse) => {
            if (mouse.button === Qt.LeftButton) pickerProc.running = true;
            else managerProc.running = true;
        }
    }
}
