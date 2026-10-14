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

    // ---- nothing planned now: what would help most ------------------------
    // Only here, when the drawer is opened: never on its own ("c'est moi qui
    // décide d'ouvrir boussole"). In a free period at school it runs to the
    // period's end; an evening with nothing on, each suggestion its own length.
    Rectangle {
        id: freeCard
        readonly property var f: root.b.nowFree
        visible: root.b.daemonConnected && freeCard.f !== null && !root.active
        width: parent.width
        height: freeCol.implicitHeight + 32
        radius: 20
        color: DrawerTheme.cardDeep
        border.width: 1
        border.color: freeCard.f && freeCard.f.school ? DrawerTheme.faint : DrawerTheme.accentStrong

        function hm(m) {
            return m >= 60 ? Math.floor(m / 60) + " h " + ("0" + (m % 60)).slice(-2) : m + " min";
        }

        Column {
            id: freeCol
            x: 16
            y: 16
            width: parent.width - 32
            spacing: 10

            Column {
                width: parent.width
                spacing: 2
                BoussoleText {
                    text: freeCard.f ? freeCard.f.label : ""
                    color: DrawerTheme.secondary
                    font.pixelSize: 11
                    font.weight: Font.Bold
                    font.letterSpacing: 1
                    font.capitalization: Font.AllUppercase
                }
                BoussoleText {
                    text: freeCard.f ? (freeCard.f.school
                                        ? freeCard.hm(freeCard.f.minutes) + root.b.tr(" ahead", " devant toi")
                                        : root.b.tr("Nothing planned", "Rien de prévu"))
                                     : ""
                    font.pixelSize: 20
                    font.weight: Font.Bold
                    font.features: { "tnum": 1 }
                }
                BoussoleText {
                    width: parent.width
                    text: freeCard.f ? freeCard.f.note : ""
                    color: DrawerTheme.secondary
                    font.pixelSize: 13
                }
            }

            BoussoleFree {
                width: parent.width
                span: freeCard.f ? freeCard.f.minutes : 0
                school: freeCard.f ? freeCard.f.school : false
                until: freeCard.f ? freeCard.f.until : ""
            }
        }
    }

    // ---- the programme slipping: one line, the most pressing ---------------
    Rectangle {
        id: slip
        readonly property var short: (root.b.programme || {}).short || null
        visible: root.b.daemonConnected && slip.short !== null
        width: parent.width
        height: slipCol.implicitHeight + 28
        radius: 18
        color: DrawerTheme.card
        border.width: 1
        border.color: "#ff9f5a"
        Column {
            id: slipCol
            x: 16
            y: 14
            width: parent.width - 32
            spacing: 8
            BoussoleText {
                width: parent.width
                text: slip.short
                      ? (slip.short.domain === "RESEAUX" ? root.b.tr("Networks", "Réseaux") : slip.short.domain)
                        + root.b.tr(" does not fit before ", " ne tient pas avant le ") + slip.short.date
                      : ""
                font.weight: Font.Bold
            }
            BoussoleText {
                width: parent.width
                text: {
                    if (!slip.short) return "";
                    const undated = ((root.b.programme || {}).undated || []).map(d => d === "RESEAUX" ? root.b.tr("Networks", "Réseaux") : d);
                    let t = root.b.tr((-slip.short.margin) + " sessions short.", "Il manque " + (-slip.short.margin) + " séances.");
                    if (undated.length) t += " " + undated.join(root.b.tr(" and ", " et ")) + root.b.tr(" have no exam date.", (undated.length > 1 ? " n'ont pas" : " n'a pas") + " de date d'examen.");
                    return t;
                }
                color: DrawerTheme.secondary
                font.pixelSize: 13
            }
            Row {
                spacing: 8
                BoussolePill {
                    primary: true
                    text: root.b.tr("See the levers", "Voir les leviers")
                    onClicked: root.b.openProgramme("whatif")
                }
                BoussolePill {
                    text: root.b.tr("The programme", "Le programme")
                    onClicked: root.b.openProgramme("")
                }
            }
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
            // A project with a folder: all its files, in any order. The
            // first one not read yet comes forward; a click opens any.
            Repeater {
                model: root.current ? root.current.parts.filter(p => p.files && p.files.length > 0) : []
                delegate: Column {
                    id: proj
                    required property var modelData
                    readonly property int read: proj.modelData.files.filter(f => f.state === "read").length
                    width: nowCol.width
                    spacing: 2
                    topPadding: 6
                    BoussoleText {
                        text: root.b.tr("Its files · ", "Ses fichiers · ") + proj.read + " / " + proj.modelData.files.length
                            + root.b.tr(" read", " lus")
                        color: DrawerTheme.secondary
                        font.pixelSize: 11
                        font.weight: Font.Bold
                        font.letterSpacing: 1
                        font.capitalization: Font.AllUppercase
                    }
                    Repeater {
                        model: proj.modelData.files
                        delegate: Rectangle {
                            id: fileRow
                            required property var modelData
                            readonly property bool isNext: fileRow.modelData.state === "next"
                            width: proj.width
                            height: fileName.implicitHeight + 12
                            radius: 10
                            color: fileHit.containsMouse ? DrawerTheme.cardHover : "transparent"
                            border.width: fileRow.isNext ? 1 : 0
                            border.color: DrawerTheme.faint
                            BoussoleText {
                                id: mark
                                x: 8
                                anchors.verticalCenter: parent.verticalCenter
                                text: fileRow.modelData.state === "read" ? "✓" : fileRow.isNext ? "→" : "·"
                                color: fileRow.modelData.state === "read" ? DrawerTheme.secondary : DrawerTheme.primary
                                font.pixelSize: 13
                            }
                            BoussoleText {
                                id: fileName
                                anchors.left: mark.right
                                anchors.leftMargin: 8
                                anchors.right: fileDetail.left
                                anchors.rightMargin: 8
                                anchors.verticalCenter: parent.verticalCenter
                                wrapMode: Text.NoWrap
                                elide: Text.ElideRight
                                text: (fileRow.modelData.num ? fileRow.modelData.num + "  " : "")
                                    + String(fileRow.modelData.title).replace(/^Séance( TP\d)? — /, "")
                                color: fileRow.modelData.state === "read" ? DrawerTheme.secondary : DrawerTheme.primary
                                font.pixelSize: 13
                                font.weight: fileRow.isNext ? Font.DemiBold : Font.Normal
                            }
                            BoussoleText {
                                id: fileDetail
                                anchors.right: parent.right
                                anchors.rightMargin: 8
                                anchors.verticalCenter: parent.verticalCenter
                                wrapMode: Text.NoWrap
                                text: fileRow.modelData.detail || ""
                                color: DrawerTheme.secondary
                                font.pixelSize: 11
                            }
                            MouseArea {
                                id: fileHit
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.b.openItem(fileRow.modelData.id)
                            }
                        }
                    }
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
                // Paused (by hand, or by a game launched anyway): it goes on
                // from here, in front of its file in focus mode.
                BoussolePill {
                    visible: root.active !== null && root.active.state === "paused"
                    primary: true
                    text: root.b.tr("Resume", "Reprendre")
                    onClicked: root.b.resumeSession()
                }
                BoussolePill {
                    visible: root.active !== null && root.active.state === "started"
                    text: root.b.tr("Pause", "Pause")
                    onClicked: root.b.pauseSession()
                }
                BoussolePill {
                    visible: root.active !== null
                    primary: root.active !== null && root.active.state !== "paused"
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
    // Not while the free-time card above offers the same, better aimed.
    Column {
        visible: root.b.daemonConnected && !root.b.setupNeeded && !root.active && !freeCard.visible
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
        BoussoleFree { width: parent.width }
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
