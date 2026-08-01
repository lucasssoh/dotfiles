import QtQuick
import Quickshell
import Quickshell.Io

// Top-left system info panel. Replaces dashboard-fastfetch.sh (fastfetch
// running inside a pinned wezterm window). Deliberately NOT a fastfetch
// wrapper: fastfetch's output is ANSI-art meant for a terminal, not
// something worth parsing into QML. Same information (OS, kernel,
// uptime, CPU, memory), plain text, native panel — swap/extend the
// fields in `infoProc.command` below if you want more (or less).

PanelWindow {
    id: root

    focusable: false
    exclusiveZone: 0
    aboveWindows: true

    anchors { top: true; left: true }
    margins { top: 64; left: 64 }

    implicitWidth: 480
    implicitHeight: 220
    color: "transparent"

    property string infoText: "Loading…"

    Process {
        id: infoProc
        command: ["bash", "-c",
            "printf 'OS       %s\\n' \"$(. /etc/os-release; echo $PRETTY_NAME)\"; " +
            "printf 'Kernel   %s\\n' \"$(uname -r)\"; " +
            "printf 'Uptime   %s\\n' \"$(uptime -p)\"; " +
            "printf 'CPU      %s\\n' \"$(lscpu | awk -F: '/Model name/ {gsub(/^ +/,\"\",$2); print $2; exit}')\"; " +
            "printf 'Memory   %s\\n' \"$(free -h | awk '/^Mem:/ {print $3\"/\"$2}')\""
        ]
        stdout: StdioCollector {
            onStreamFinished: root.infoText = this.text.trim()
        }
    }

    // Re-runs every 5s while shown (uptime/memory drift); no timer at
    // all runs while hidden, unlike the old wezterm-per-widget process.
    Timer {
        interval: 5000
        running: root.visible
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            if (!infoProc.running) infoProc.running = true;
        }
    }

    Rectangle {
        anchors.fill: parent
        radius: 16
        color: "#1c1c1e"    // colors.lua: background
        opacity: 0.85
        border.width: 1
        border.color: "#2c2c2e"  // colors.lua: surface

        Text {
            anchors.fill: parent
            anchors.margins: 24
            text: root.infoText
            color: "#e5e5ea"  // colors.lua: text
            font.family: "SF Pro Text"
            font.pixelSize: 15
            lineHeight: 1.6
            wrapMode: Text.NoWrap
        }
    }
}
