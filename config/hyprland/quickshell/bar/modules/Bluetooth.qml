import QtQuick
import Quickshell.Io

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

    property string text: ""

    implicitWidth: Math.max(label.implicitWidth + 20, 70)
    implicitHeight: 24

    function poll() { if (!proc.running) proc.running = true; }

    Process {
        id: proc
        command: ["bash", "-c", `
p=$(bluetoothctl show 2>/dev/null | awk -F': ' '/Powered/ {print $2}')
dev=$(bluetoothctl devices Connected 2>/dev/null | awk '{print $2; exit}')
if [ "$p" != "yes" ]; then
    printf '󰂲'
elif [ -n "$dev" ]; then
    batt=$(bluetoothctl info "$dev" 2>/dev/null | awk -F'[()]' '/Battery Percentage/ {print $2}' | tr -d '%')
    if [ -n "$batt" ]; then
        printf '󰂱  %s%%' "$batt"
    else
        printf '󰂱'
    fi
else
    printf '󰂯'
fi
`]
        stdout: StdioCollector {
            onStreamFinished: root.text = this.text.trim()
        }
    }

    Timer {
        interval: 8000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.poll()
    }

    Text {
        id: label
        anchors.centerIn: parent
        text: root.text
        color: "#f2f2f7"
        font.family: "JetBrains Mono"
        font.pixelSize: 13
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
