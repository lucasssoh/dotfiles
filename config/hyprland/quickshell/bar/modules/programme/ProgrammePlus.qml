import QtQuick
import "../../theme"
import "../../services"

// Plus: everything that can be set, without editing a file. A menu, then
// one page per subject; each page goes back to the menu.
Column {
    id: root

    spacing: 12
    readonly property var b: ProgrammeState

    readonly property var upcoming: {
        const now = new Date();
        return root.b.deadlines.filter(d => new Date(d.at) >= now).sort((x, y) => x.at < y.at ? -1 : 1);
    }

    component Section: ProgrammeText {
        color: DrawerTheme.secondary
        font.pixelSize: 11
        font.weight: Font.Bold
        font.letterSpacing: 1
        font.capitalization: Font.AllUppercase
    }

    component Entry: Rectangle {
        id: entry
        property string title: ""
        property string detail: ""
        property string target: ""
        // A Lucide glyph, in a small tile ahead of the title.
        property string icon: ""
        width: root.width
        height: Math.max(56, entryCol.implicitHeight + 24)
        radius: 14
        color: entryHit.containsMouse ? DrawerTheme.cardHover : DrawerTheme.card
        Behavior on color { ColorAnimation { duration: 120 } }
        scale: entryHit.pressed ? 0.98 : 1
        Behavior on scale { NumberAnimation { duration: 90; easing.type: Easing.OutCubic } }
        Rectangle {
            id: entryIcon
            x: 12
            anchors.verticalCenter: parent.verticalCenter
            width: 34
            height: 34
            radius: 10
            color: DrawerTheme.cardRaised
            Text {
                anchors.centerIn: parent
                text: entry.icon
                color: DrawerTheme.primary
                font.family: Fonts.iconLucide
                font.pixelSize: 17
            }
        }
        Column {
            id: entryCol
            x: 58
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - 58 - 34
            spacing: 2
            ProgrammeText { width: parent.width; text: entry.title; font.weight: Font.Bold }
            ProgrammeText { width: parent.width; text: entry.detail; color: DrawerTheme.secondary; font.pixelSize: 13; visible: text !== "" }
        }
        ProgrammeText {
            anchors.verticalCenter: parent.verticalCenter
            anchors.right: parent.right
            anchors.rightMargin: 14
            text: "›"
            color: DrawerTheme.secondary
            font.pixelSize: 20
        }
        MouseArea {
            id: entryHit
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.b.openPlus(entry.target)
        }
    }

    // ---- the menu -------------------------------------------------------------
    Column {
        visible: root.b.plusPage === ""
        width: parent.width
        spacing: 10

        Entry {
            target: "deadlines"
            icon: "\ue234"
            title: root.b.tr("Exams and hand-ins", "Examens et rendus")
            detail: root.upcoming.length ? root.b.tr("next: ", "prochain : ") + root.upcoming[0].title : root.b.tr("none", "aucun")
        }
        Entry {
            target: "rhythm"
            icon: "\ue304"
            title: root.b.tr("Rhythm", "Rythme")
            detail: root.b.tr("week · holidays", "semaine · vacances")
        }
        Entry {
            target: "subjects"
            icon: "\ue05f"
            title: root.b.tr("Subjects", "Modules")
            detail: root.b.tr("level · what opens", "niveau · ce qui s'ouvre")
        }
        Entry {
            target: "calendars"
            icon: "\ue2b9"
            title: root.b.tr("Calendars", "Calendriers")
            detail: root.b.settings.calendar_url ? root.b.tr("timetable · personal", "emploi du temps · perso")
                                                 : root.b.tr("no timetable yet", "pas d'emploi du temps")
        }
        Entry {
            target: "settings"
            icon: "\ue154"
            title: root.b.tr("Settings", "Réglages")
            detail: root.b.tr("language · objective · course folder", "langue · objectif · dossier de cours")
        }
        ProgrammeText {
            topPadding: 8
            text: root.b.tr("First launch again", "Refaire le premier lancement")
            color: DrawerTheme.secondary
            font.pixelSize: 14
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.b.openSetup()
            }
        }
    }

    // ---- a sub-page -------------------------------------------------------------
    Column {
        visible: root.b.plusPage !== ""
        width: parent.width
        spacing: 12

        ProgrammeText {
            text: "‹ Plus"
            color: DrawerTheme.secondary
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.b.plusPage = ""
            }
        }
        Loader {
            width: parent.width
            sourceComponent: ({
                deadlines: deadlines, subjects: subjects,
                calendars: calendars, rhythm: rhythm, settings: settings
            })[root.b.plusPage] || null
        }
    }

    Component { id: deadlines; ProgrammePlusDeadlines {} }
    Component { id: subjects; ProgrammePlusSubjects {} }
    Component { id: calendars; ProgrammePlusCalendars {} }
    Component { id: rhythm; ProgrammePlusRhythm {} }
    Component { id: settings; ProgrammePlusSettings {} }
}
