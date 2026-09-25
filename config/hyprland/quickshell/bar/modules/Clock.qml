import QtQuick
import Quickshell
import "../theme"
import "../services"

// Native port of waybar's `clock` module (format {:%H:%M}), moved out of
// dead-center (was sharing centerRow with Workspaces -- see shell.qml)
// into the tools pill, right before the power dot -- asked for. Briefly
// a macOS-menu-bar-style "Fri Aug 28 20:32" string, then a plain time
// while the day/date lived elsewhere, and now a date again -- but AFTER
// the time ("ajouter Fri Sep 18 à droite de 22:11"), not before it.

Item {
    id: root
    // The ink ramp this module draws with. Points at the dark-material
    // singleton by default, which is what every call site below used
    // directly before this property existed -- so this changes nothing on
    // its own. It exists so the band's islands can hand a LIGHT ramp to
    // the modules sitting on them, per island, without touching any of
    // those call sites again. See theme/Ink.qml's MATERIAL note for why
    // the material flips rather than the ink alone.
    property QtObject ink: Ink

    // Which bar was clicked, so the calendar drawer opens on THIS
    // monitor -- same hand-down Battery/BaliseButton/NotificationBell take.
    property var screen: null

    // 20 -> 12, i.e. 10px of padding a side down to 6 -- asked for ("les
    // paddings right de powerprofile et horloge sont trop grand par
    // rapport aux autres"). 6 is what ScriptModule already uses in the
    // same row, and what Performance.qml now lands on too. "HH:mm" is
    // fixed-width in practice (the leading zero is kept); the date that
    // follows it is not (one- vs two-digit days), but it only moves the
    // pill's LEFT edge -- toolsIsland is anchored by its right one.
    implicitWidth: label.implicitWidth + 12
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
        // en_US locale rather than Qt.formatDateTime, which would follow
        // this session's fr_FR one and render "ven. 18 sept." -- same
        // reasoning, and the same "Fri Sep 18" shape, as
        // NotificationCenter.qml's own header clock.
        text: Qt.formatDateTime(clock.date, "HH:mm") + "  " + clock.date.toLocaleDateString(Qt.locale("en_US"), "ddd MMM d")
        color: root.ink.primary
        font.family: Fonts.ui
        font.pixelSize: 14
    }

    // A click opens the month calendar (CalendarState / calendar/
    // CalendarHome.qml), TOOLS' fifth drawer.
    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: CalendarState.togglePanel(root.screen)
    }
}
