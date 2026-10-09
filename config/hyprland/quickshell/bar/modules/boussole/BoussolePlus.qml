import QtQuick
import "../../theme"
import "../../services"

// Plus: everything that can be set, without editing a file. A menu, then
// one page per subject; each page goes back to the menu.
Column {
    id: root

    spacing: 12
    readonly property var b: BoussoleState

    readonly property var upcoming: {
        const now = new Date();
        return root.b.deadlines.filter(d => new Date(d.at) >= now).sort((x, y) => x.at < y.at ? -1 : 1);
    }

    component Section: BoussoleText {
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
            BoussoleText { width: parent.width; text: entry.title; font.weight: Font.Bold }
            BoussoleText { width: parent.width; text: entry.detail; color: DrawerTheme.secondary; font.pixelSize: 13; visible: text !== "" }
        }
        BoussoleText {
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

        Section { text: root.b.tr("What sets the priorities", "Ce qui fixe les priorités") }
        Entry {
            target: "deadlines"
            icon: "\ue234"
            title: root.b.tr("Exams and hand-ins", "Examens et rendus")
            detail: root.upcoming.length + root.b.tr(" ahead", " à venir")
                    + (root.upcoming.length ? root.b.tr(" · next: ", " · prochain : ") + root.upcoming[0].title : "")
        }
        Entry {
            target: "projects"
            icon: "\ue4c6"
            title: root.b.tr("Projects", "Projets")
            detail: root.b.projects.length === 0 ? root.b.tr("none", "aucun") : root.b.projects.map(p => p.name).join(" · ")
        }
        Entry {
            target: "campaign"
            icon: "\ue062"
            title: root.b.tr("Campaigns", "Campagnes")
            detail: root.b.campaigns.length === 0 ? root.b.tr("none", "aucune")
                    : root.b.campaigns.map(c => c.name + (c.closed ? root.b.tr(" (closed)", " (close)") : " · " + c.rows.length)).join(" · ")
        }
        Section { text: root.b.tr("What describes your life", "Ce qui décrit ta vie") }
        Entry {
            target: "subjects"
            icon: "\ue05f"
            title: root.b.tr("Subjects", "Matières")
            detail: (root.b.settings.domains || []).filter(d => !d.archived).map(d => d.id).join(" · ")
        }
        Entry {
            target: "calendars"
            icon: "\ue2b9"
            title: root.b.tr("Calendars", "Calendriers")
            detail: root.b.settings.calendar_url ? root.b.tr("timetable set · personal agenda", "emploi du temps relié · agenda perso")
                                                 : root.b.tr("no timetable yet", "pas encore d'emploi du temps")
        }
        Entry {
            target: "rhythm"
            icon: "\ue304"
            title: root.b.tr("Rhythm and periods", "Rythme et périodes")
            detail: root.b.tr("typical week · holidays · status", "semaine type · vacances · statut")
        }
        Section { text: root.b.tr("The app", "L'appli") }
        Rectangle {
            width: root.width
            height: 56
            radius: 14
            color: rerunHit.containsMouse ? DrawerTheme.cardHover : "transparent"
            Behavior on color { ColorAnimation { duration: 120 } }
            border.width: 1
            border.color: DrawerTheme.faint
            Rectangle {
                x: 12
                anchors.verticalCenter: parent.verticalCenter
                width: 34
                height: 34
                radius: 10
                color: DrawerTheme.cardRaised
                Text {
                    anchors.centerIn: parent
                    text: "\ue0d1"
                    color: DrawerTheme.primary
                    font.family: Fonts.iconLucide
                    font.pixelSize: 17
                }
            }
            Column {
                x: 58
                anchors.verticalCenter: parent.verticalCenter
                BoussoleText { text: root.b.tr("Run the first launch again", "Refaire le premier lancement"); font.weight: Font.Bold }
                BoussoleText { text: root.b.tr("nothing is erased, every step is pre-filled", "rien n'est effacé, chaque étape est préremplie"); color: DrawerTheme.secondary; font.pixelSize: 13 }
            }
            MouseArea {
                id: rerunHit
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.b.openSetup()
            }
        }
        Entry {
            target: "settings"
            icon: "\ue154"
            title: root.b.tr("Settings", "Réglages")
            detail: root.b.tr("language, objective, game lock, course folder", "langue, objectif, verrouillage, dossier de cours")
        }
    }

    // ---- a sub-page -------------------------------------------------------------
    Column {
        visible: root.b.plusPage !== ""
        width: parent.width
        spacing: 12

        BoussoleText {
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
                deadlines: deadlines, projects: projects, campaign: campaign, subjects: subjects,
                calendars: calendars, rhythm: rhythm, settings: settings
            })[root.b.plusPage] || null
        }
    }

    Component { id: deadlines; BoussolePlusDeadlines {} }
    Component { id: projects; BoussolePlusProjects {} }
    Component { id: campaign; BoussolePlusCampaign {} }
    Component { id: subjects; BoussolePlusSubjects {} }
    Component { id: calendars; BoussolePlusCalendars {} }
    Component { id: rhythm; BoussolePlusRhythm {} }
    Component { id: settings; BoussolePlusSettings {} }
}
