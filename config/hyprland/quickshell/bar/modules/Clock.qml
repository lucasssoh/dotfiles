import QtQuick
import Quickshell
import "../theme"

// Native port of waybar's `clock` module (format {:%H:%M}).

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
        font.pixelSize: 13
    }
}
