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
//
// HyperOS pass: moved again, to the far LEFT of the bar, on its own
// island (see shell.qml's `clockIsland`) -- the Android/HyperOS status
// bar convention, and the single move that most separates this bar from
// macOS's menu bar, whose clock lives at the far right. Time and date are
// two Texts but ONE style -- primary ink, 13px Medium: a DemiBold time
// over a grey date was tried and read as two different accents (asked
// for: "uniformise"). The date keeps its "Sun Sep 27" shape.

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

    Row {
        id: label
        anchors.centerIn: parent
        spacing: 8

        Text {
            renderType: Text.NativeRendering
            font.hintingPreference: Font.PreferNoHinting
            anchors.baseline: dateText.baseline
            text: Qt.formatDateTime(clock.date, "HH:mm")
            color: root.ink.primary
            font.family: Fonts.ui
            font.pixelSize: 13
            font.weight: Font.Medium
        }

        Text {
            id: dateText
            renderType: Text.NativeRendering
            font.hintingPreference: Font.PreferNoHinting
            anchors.verticalCenter: parent.verticalCenter
            // en_US locale rather than Qt.formatDateTime, which would
            // follow this session's fr_FR one and render "ven. 18 sept."
            // -- same reasoning, and the same "Fri Sep 18" shape, as
            // NotificationCenter.qml's own header clock.
            text: clock.date.toLocaleDateString(Qt.locale("en_US"), "ddd MMM d")
            color: root.ink.primary
            font.family: Fonts.ui
            font.pixelSize: 13
            font.weight: Font.Medium
        }
    }

    // A click opens the month calendar (CalendarState / calendar/
    // CalendarHome.qml), hosted by the clock's own island.
    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: CalendarState.togglePanel(root.screen)
    }
}
