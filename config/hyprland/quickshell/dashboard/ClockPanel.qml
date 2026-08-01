import QtQuick
import Quickshell

// Bottom-right clock panel. Replaces dashboard-clock.sh (tty-clock
// running inside a pinned wezterm window). Colors match the palette in
// hypr/colors.lua (accent2 = light cyan, used here for the time; subtle
// = muted grey, for the date).

PanelWindow {
    id: root

    focusable: false
    exclusiveZone: 0        // never reserves screen space / pushes waybar
    aboveWindows: true

    anchors { bottom: true; right: true }
    margins { bottom: 64; right: 64 }

    implicitWidth: 420
    implicitHeight: 160
    color: "transparent"    // QsWindow.color defaults to white otherwise

    SystemClock {
        id: clock
        precision: SystemClock.Seconds
    }

    Rectangle {
        anchors.fill: parent
        radius: 16
        color: "#1c1c1e"    // colors.lua: background
        opacity: 0.85
        border.width: 1
        border.color: "#2c2c2e"  // colors.lua: surface

        Column {
            anchors.centerIn: parent
            spacing: 4

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: Qt.formatDateTime(clock.date, "HH:mm:ss")
                color: "#d0ffff"  // colors.lua: accent2
                font.family: "SF Pro Display"
                font.pixelSize: 56
                font.bold: true
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: Qt.formatDateTime(clock.date, "dddd d MMMM")
                color: "#8e8e93"  // colors.lua: subtle
                font.family: "SF Pro Text"
                font.pixelSize: 16
            }
        }
    }
}
