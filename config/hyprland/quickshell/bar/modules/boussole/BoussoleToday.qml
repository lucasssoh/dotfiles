import QtQuick
import "../../theme"
import "../../services"

// Today: sessions left open first, then the session under way or the next
// one with what to do now, then the day as the timetable and the plan make
// it -- courses filled, sessions outlined, free periods dashed.
Column {
    id: root

    spacing: 14

    readonly property var b: BoussoleState
    readonly property var t: b.tracking
    // Under way: started or paused, whether or not it is being measured.
    readonly property var active: {
        for (const r of root.b.today) if (r.state === "started" || r.state === "paused") return r;
        return null;
    }
    readonly property var upcoming: {
        for (const r of root.b.today)
            if (r.type === "session" && !r.past && (r.state === "planned" || r.state === "postponed")) return r;
        return null;
    }
    readonly property var current: root.active || root.upcoming
    // Said "not tonight" today and not over yet: they can come back.
    readonly property var skipped: root.b.today.filter(r => r.state === "skipped" && !r.past)
    property string freeNote: ""

    BoussoleText {
        visible: !root.b.daemonConnected
        width: parent.width
        text: root.b.tr("The Boussole service is not running.", "Le service Boussole ne tourne pas.")
        color: DrawerTheme.secondary
    }

    // ---- nothing set up yet ------------------------------------------------
    Rectangle {
        visible: root.b.daemonConnected && root.b.setupNeeded
        width: parent.width
        height: setupCol.implicitHeight + 28
        radius: 18
        color: DrawerTheme.card
        Column {
            id: setupCol
            x: 16
            y: 14
            width: parent.width - 32
            spacing: 8
            BoussoleText { width: parent.width; text: root.b.tr("Let's set Boussole up", "On règle Boussole"); font.pixelSize: 17; font.weight: Font.Bold }
            BoussoleText {
                width: parent.width
                text: root.b.tr("Five short steps: your courses, your timetable, how they go together, your rhythm. Everything can be changed later in More.",
                                "Cinq étapes courtes : tes cours, ton emploi du temps, le lien entre les deux, ton rythme. Tout se change ensuite dans Plus.")
                color: DrawerTheme.secondary
                font.pixelSize: 13
            }
            BoussolePill { primary: true; text: root.b.tr("Start", "Commencer"); onClicked: root.b.openSetup() }
        }
    }

    // ---- just closed: a way back ------------------------------------------
    Rectangle {
        visible: root.b.justClosed !== ""
        width: parent.width
        height: 52
        radius: 16
        color: DrawerTheme.card
        BoussoleText {
            anchors.verticalCenter: parent.verticalCenter
            x: 16
            text: root.b.tr("Session closed", "Séance close")
            font.weight: Font.Bold
        }
        BoussolePill {
            anchors.verticalCenter: parent.verticalCenter
            anchors.right: parent.right
            anchors.rightMargin: 6
            text: root.b.tr("Undo", "Annuler")
            onClicked: root.b.undoClose()
        }
    }

    // ---- left open --------------------------------------------------------
    Rectangle {
        visible: root.b.declare.length > 0
        width: parent.width
        height: declareCol.implicitHeight + 28
        radius: 18
        color: DrawerTheme.card

        Column {
            id: declareCol
            x: 16
            y: 14
            width: parent.width - 32
            spacing: 8

            Row {
                spacing: 8
                Rectangle { width: 8; height: 8; radius: 4; color: DrawerTheme.danger; anchors.verticalCenter: parent.verticalCenter }
                BoussoleText {
                    text: root.b.declare.length === 1
                        ? root.b.tr("A session was left open", "Une séance est restée ouverte")
                        : root.b.declare.length + root.b.tr(" sessions were left open", " séances sont restées ouvertes")
                    font.pixelSize: 15
                    font.weight: Font.Bold
                }
            }
            BoussoleText {
                width: parent.width
                text: root.b.tr("Say how far you went: what is not done comes back first, nothing is lost.",
                                "Dis jusqu'où tu es allé : ce qui n'est pas fait repart en tête, rien n'est perdu.")
                color: DrawerTheme.secondary
                font.pixelSize: 13
            }
            Flow {
                width: parent.width
                spacing: 8
                Repeater {
                    model: root.b.declare
                    delegate: BoussolePill {
                        required property var modelData
                        text: root.b.tr("Declare ", "Déclarer ") + modelData.slice(5, 10).split("-").reverse().join("/")
                        onClicked: root.b.openClose(modelData)
                    }
                }
            }
        }
    }

    // ---- now --------------------------------------------------------------
    Rectangle {
        visible: root.current !== null
        width: parent.width
        height: nowCol.implicitHeight + 28
        radius: 18
        color: DrawerTheme.card
        border.width: root.active ? 1 : 0
        border.color: DrawerTheme.faint

        Column {
            id: nowCol
            x: 16
            y: 14
            width: parent.width - 32
            spacing: 6

            BoussoleText {
                text: root.active && root.t
                    ? (root.t.counting ? root.b.tr("Under way · ", "En cours · ") : root.b.tr("Paused · ", "En pause · "))
                      + Math.floor(root.b.effectiveSecs / 60) + root.b.tr(" min effective", " min effectives")
                    : (root.current ? root.current.start + " – " + root.current.end : "")
                color: DrawerTheme.secondary
                font.pixelSize: 12
                font.weight: Font.Bold
                font.capitalization: Font.AllUppercase
                font.letterSpacing: 0.8
            }
            BoussoleText {
                width: parent.width
                text: root.current ? root.current.title : ""
                font.pixelSize: 17
                font.weight: Font.Bold
            }
            Repeater {
                model: root.current ? root.current.parts : []
                delegate: BoussoleText {
                    required property var modelData
                    width: nowCol.width
                    text: (modelData.domain ? modelData.domain + " · " : "") + modelData.what + " · " + modelData.minutes + " min"
                    color: DrawerTheme.secondary
                    font.pixelSize: 14
                }
            }
            Item { width: 1; height: 4 }
            Flow {
                width: parent.width
                spacing: 8
                BoussolePill {
                    visible: !root.active
                    primary: true
                    text: root.b.tr("Start", "Commencer")
                    onClicked: root.b.start(root.current.id)
                }
                BoussolePill {
                    visible: !root.active
                    text: root.b.tr("Not tonight", "Pas ce soir")
                    onClicked: root.b.skip(root.current.id)
                }
                BoussolePill {
                    visible: root.active !== null
                    primary: true
                    text: root.b.tr("Close…", "Clore…")
                    onClicked: root.b.openClose(root.active.id)
                }
            }
        }
    }

    // ---- said "not tonight", by mistake maybe -----------------------------
    Rectangle {
        visible: root.skipped.length > 0
        width: parent.width
        height: skippedCol.implicitHeight + 28
        radius: 18
        color: "transparent"
        border.width: 1
        border.color: DrawerTheme.faint
        Column {
            id: skippedCol
            x: 16
            y: 14
            width: parent.width - 32
            spacing: 8
            BoussoleText {
                text: root.b.tr("Not tonight", "Pas ce soir")
                color: DrawerTheme.secondary
                font.pixelSize: 11
                font.weight: Font.Bold
                font.letterSpacing: 1
                font.capitalization: Font.AllUppercase
            }
            Repeater {
                model: root.skipped
                delegate: Item {
                    required property var modelData
                    width: skippedCol.width
                    height: Math.max(skippedTitle.implicitHeight, back.height)
                    BoussoleText {
                        id: skippedTitle
                        anchors.left: parent.left
                        anchors.right: back.left
                        anchors.rightMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        text: modelData.start + "  " + modelData.title
                        elide: Text.ElideRight
                        font.pixelSize: 14
                    }
                    BoussolePill {
                        id: back
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.b.tr("Bring back", "Reprendre")
                        onClicked: root.b.unskip(modelData.id)
                    }
                }
            }
        }
    }

    // ---- I have time ------------------------------------------------------
    Column {
        visible: root.b.daemonConnected && !root.b.setupNeeded && !root.active
        width: parent.width
        spacing: 8
        BoussoleText {
            text: root.b.tr("I have time", "J'ai du temps")
            color: DrawerTheme.secondary
            font.pixelSize: 11
            font.weight: Font.Bold
            font.letterSpacing: 1
            font.capitalization: Font.AllUppercase
        }
        Flow {
            width: parent.width
            spacing: 8
            Repeater {
                model: [30, 45, 60, 90]
                delegate: BoussoleChip {
                    required property var modelData
                    text: modelData < 60 ? modelData + " min" : Math.floor(modelData / 60) + " h" + (modelData % 60 ? " " + (modelData % 60) : "")
                    onClicked: root.b.freeTime(modelData, r => root.freeNote = r.text || "")
                }
            }
        }
        BoussoleText {
            visible: root.freeNote !== ""
            width: parent.width
            text: root.freeNote
            color: DrawerTheme.secondary
            font.pixelSize: 13
        }
    }

    // ---- the day ----------------------------------------------------------
    BoussoleText {
        visible: root.b.today.length > 0
        text: root.b.tr("The day", "La journée")
        color: DrawerTheme.secondary
        font.pixelSize: 11
        font.weight: Font.Bold
        font.letterSpacing: 1
        font.capitalization: Font.AllUppercase
    }

    BoussoleDay {
        width: parent.width
        rows: root.b.today
    }

    BoussoleText {
        visible: root.b.daemonConnected && root.b.today.length === 0
        width: parent.width
        text: root.b.paused ? root.b.tr("Paused: no sessions for now.", "En pause : pas de séance pour l'instant.")
                            : root.b.tr("Nothing planned today.", "Rien de prévu aujourd'hui.")
        color: DrawerTheme.secondary
    }
}
