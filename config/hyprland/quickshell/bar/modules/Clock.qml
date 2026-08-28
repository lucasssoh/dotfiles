import QtQuick
import Quickshell
import "../theme"

// Native port of waybar's `clock` module (format {:%H:%M}), moved out of
// dead-center (was sharing centerRow with Workspaces -- see shell.qml)
// into the tools pill, right before the power dot -- asked for. Briefly
// a macOS-menu-bar-style "Fri Aug 28 20:32" string, simplified back to a
// plain time -- the day/date now live in Balise's own home header
// instead (see ui/home.rs's clock header comment).

Item {
    id: root
    implicitWidth: label.implicitWidth + 20
    implicitHeight: 24

    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }

    Text {
        renderType: Text.NativeRendering
        font.hintingPreference: Font.PreferNoHinting
        id: label
        anchors.centerIn: parent
        text: Qt.formatDateTime(clock.date, "HH:mm")
        color: "#f2f2f7"
        font.family: Fonts.ui
        font.pixelSize: 14
    }
}
