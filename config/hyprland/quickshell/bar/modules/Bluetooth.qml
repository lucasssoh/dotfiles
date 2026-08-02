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
// Battery %: BlueZ only populates "Battery Percentage: 0x.. (NN%)" in
// `bluetoothctl info` once a device with battery reporting is actually
// connected -- format assumed from BlueZ convention, not verified live
// (no device was connected while writing this).

Item {
    id: root

    property string icon: ""
    property string batteryText: ""

    // 70 (matched the other audio modules' floor) assumed a battery %
    // was usually showing next to the icon -- in practice batteryText is
    // empty almost all the time (BlueZ only reports it for a connected
    // device that supports battery reporting), so that floor was mostly
    // just dead reserved space. Just enough padding around the icon
    // alone now (same idea as ScriptModule's icon-only 30 floor).
    //
    // Asymmetric on purpose (10 left, 4 right) instead of the usual
    // centered/symmetric padding every other module uses: this block's
    // order is now audio out/in, bluetooth, network (see shell.qml) --
    // network's rate text is the one value here that visibly changes
    // width, so it keeps its own full breathing room on the block's free
    // right edge, and the tightening asked for between bluetooth and it
    // comes out of bluetooth's right side specifically, not network's.
    implicitWidth: Math.max(label.implicitWidth + 14, 24)
    implicitHeight: 24

    function poll() { if (!proc.running) proc.running = true; }

    Process {
        id: proc
        // "icon|batteryText" -- the icon glyph and the battery % need
        // separate Text items now (see Fonts.qml's `icon` vs `ui`), so
        // this prints them delimited instead of one pre-joined string,
        // split back apart client-side below.
        command: ["bash", "-c", `
p=$(bluetoothctl show 2>/dev/null | awk -F': ' '/Powered/ {print $2}')
dev=$(bluetoothctl devices Connected 2>/dev/null | awk '{print $2; exit}')
if [ "$p" != "yes" ]; then
    printf '󰂲|'
elif [ -n "$dev" ]; then
    batt=$(bluetoothctl info "$dev" 2>/dev/null | awk -F'[()]' '/Battery Percentage/ {print $2}' | tr -d '%')
    if [ -n "$batt" ]; then
        printf '󰂱|%s%%' "$batt"
    else
        printf '󰂱|'
    fi
else
    printf '󰂯|'
fi
`]
        stdout: StdioCollector {
            onStreamFinished: {
                const parts = this.text.trim().split("|");
                root.icon = parts[0] || "";
                root.batteryText = parts[1] || "";
            }
        }
    }

    Timer {
        interval: 8000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.poll()
    }

    Row {
        id: label
        anchors.left: parent.left
        anchors.leftMargin: 10
        anchors.verticalCenter: parent.verticalCenter
        spacing: 4

        Text {
            renderType: Text.NativeRendering
            font.hintingPreference: Font.PreferNoHinting
            text: root.icon
            color: "#f2f2f7"
            font.family: Fonts.icon
            font.pixelSize: 13
        }
        Text {
            renderType: Text.NativeRendering
            font.hintingPreference: Font.PreferNoHinting
            text: root.batteryText
            visible: root.batteryText !== ""
            color: "#f2f2f7"
            font.family: Fonts.ui
            font.pixelSize: 13
        }
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
