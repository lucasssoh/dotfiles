import QtQuick
import Quickshell.Io
import "../theme"

// Native-ish port of waybar's `bluetooth` module. No clean push source
// exists for BlueZ state (see shell.qml v2 header on why this stayed a
// poll rather than a stream), but 45s was too slow -- dropped to 8s,
// and the two actions that actually change bluetooth state from this
// bar (orbit's picker, blueman-manager) now run as real Processes with
// onExited re-polling immediately, so at least "I just used the picker"
// feels instant instead of waiting out the interval.
//
// Icon-only, no battery % (asked for, to save space) -- was showing
// BlueZ's connected-device battery reading next to the glyph.

Item {
    id: root

    property string state: "off"   // "off" | "on" | "connected"

    // Icon-only now (battery % dropped -- asked for, to save space):
    // same narrow floor as Performance.qml's own icon-only module.
    implicitWidth: Math.max(iconText.implicitWidth + 12, 24)
    implicitHeight: 24

    function poll() { if (!proc.running) proc.running = true; }

    Process {
        id: proc
        // No more battery-percentage lookup (bluetoothctl info + a
        // second awk pass) -- dropped along with the UI that displayed
        // it, not just hidden: one less subprocess call per poll.
        command: ["bash", "-c", `
p=$(bluetoothctl show 2>/dev/null | awk -F': ' '/Powered/ {print $2}')
dev=$(bluetoothctl devices Connected 2>/dev/null | awk '{print $2; exit}')
if [ "$p" != "yes" ]; then
    printf 'off'
elif [ -n "$dev" ]; then
    printf 'connected'
else
    printf 'on'
fi
`]
        stdout: StdioCollector {
            onStreamFinished: root.state = this.text.trim() || "off"
        }
    }

    Timer {
        interval: 8000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.poll()
    }

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
        font.pixelSize: 15
    }

    Process {
        id: pickerProc
        command: ["bash", "-c", "$HOME/.config/waybar/scripts/orbit-toggle.sh bluetooth"]
        onExited: root.poll()
    }

    Process {
        id: managerProc
        command: ["blueman-manager"]
        onExited: root.poll()
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
