import QtQuick
import "../../theme"
import "../../services"

// Today: the session under way, those saved to take up again, the next
// one, a session started now, and what comes after. Nothing is suggested
// unless asked for ("c'est moi qui décide d'ouvrir boussole").
Column {
    id: root

    spacing: 26

    readonly property var b: BoussoleState
    readonly property var t: b.tracking
    // Under way: started or paused, whether or not it is being measured.
    readonly property var active: {
        for (const r of root.b.today) if (r.state === "started") return r;
        return null;
    }
    readonly property var saved: root.b.saved.filter(s => !root.active || s.id !== root.active.id)
    readonly property var next: root.b.status.then || null
    // "Later" opened on the next session: until when.
    property bool choosing: false
    property bool starting: false
    onChoosingChanged: root.b.laterTyping = root.choosing
    Connections {
        target: root.b
        function onPanelOpenChanged() { if (!root.b.panelOpen) { root.choosing = false; root.starting = false; } }
    }

    function hm(m) {
        return m >= 60 ? Math.floor(m / 60) + " h" + (m % 60 ? " " + ("0" + (m % 60)).slice(-2) : "") : m + " min";
    }
    function minutes(a, z) {
        const p = (a || "0:0").split(":"), q = (z || "0:0").split(":");
        return (+q[0] * 60 + +q[1]) - (+p[0] * 60 + +p[1]);
    }
    readonly property string todayIso: Qt.formatDate(new Date(root.b.nowMs), "yyyy-MM-dd")

    component Label: BoussoleText {
        color: DrawerTheme.secondary
        font.pixelSize: 13
        font.weight: Font.Medium
    }

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
        height: setupCol.implicitHeight + 36
        radius: 20
        color: DrawerTheme.card
        Column {
            id: setupCol
            x: 18
            y: 18
            width: parent.width - 36
            spacing: 12
            BoussoleText { width: parent.width; text: root.b.tr("Set Boussole up", "Régler Boussole"); font.pixelSize: 17; font.weight: Font.DemiBold }
            BoussolePill { primary: true; text: root.b.tr("Start", "Commencer"); onClicked: root.b.openSetup() }
        }
    }

    // ---- Later holds -----------------------------------------------------
    Rectangle {
        visible: root.b.daemonConnected && root.b.away !== "" && !root.active
        width: parent.width
        height: 64
        radius: 20
        color: DrawerTheme.clear(DrawerTheme.card)
        border.width: 1
        border.color: DrawerTheme.faint
        BoussoleText {
            x: 18
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - 36 - backPill.width
            text: root.b.tr("Nothing ", "Rien ") + root.b.away
            font.pixelSize: 15
            font.weight: Font.DemiBold
            elide: Text.ElideRight
        }
        BoussolePill {
            id: backPill
            anchors.right: parent.right
            anchors.rightMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            text: root.b.tr("Back now", "De retour")
            onClicked: root.b.back()
        }
    }

    // ---- under way ---------------------------------------------------------
    Column {
        visible: root.active !== null
        width: parent.width
        spacing: 10
        Label { text: root.b.tr("Under way", "En cours") }
        Rectangle {
            width: parent.width
            height: activeCol.implicitHeight + 36
            radius: 20
            color: DrawerTheme.card
            Column {
                id: activeCol
                x: 18
                y: 18
                width: parent.width - 36
                spacing: 14
                Item {
                    width: parent.width
                    height: activeTitle.implicitHeight
                    BoussoleText {
                        id: activeTitle
                        text: root.active ? root.active.title : ""
                        font.pixelSize: 24
                        font.weight: Font.DemiBold
                    }
                    BoussoleText {
                        anchors.right: parent.right
                        anchors.baseline: activeTitle.baseline
                        text: root.t ? Math.floor(root.b.effectiveSecs / 60) + root.b.tr(" min", " min") : ""
                        color: DrawerTheme.secondary
                        font.pixelSize: 14
                    }
                }
                Row {
                    spacing: 8
                    BoussolePill {
                        text: root.b.tr("Save & leave", "Sauver, partir")
                        onClicked: root.b.pauseSession()
                    }
                    BoussolePill {
                        text: root.b.tr("Close", "Clore")
                        onClicked: root.b.openClose(root.active.id)
                    }
                }
            }
        }
    }

    // ---- just closed: a way back -------------------------------------------
    Rectangle {
        visible: root.b.justClosed !== ""
        width: parent.width
        height: 56
        radius: 20
        color: DrawerTheme.card
        BoussoleText {
            anchors.verticalCenter: parent.verticalCenter
            x: 18
            text: root.b.tr("Closed", "Close")
            font.weight: Font.DemiBold
        }
        BoussolePill {
            anchors.verticalCenter: parent.verticalCenter
            anchors.right: parent.right
            anchors.rightMargin: 8
            text: root.b.tr("Undo", "Annuler")
            onClicked: root.b.undoClose()
        }
    }

    // ---- saved: take it up again ------------------------------------------
    Column {
        visible: root.saved.length > 0
        width: parent.width
        spacing: 10
        Label { text: root.b.tr("Continue", "Continuer") }
        Repeater {
            model: root.saved
            delegate: Rectangle {
                id: card
                required property var modelData
                width: root.width
                height: savedCol.implicitHeight + 36
                radius: 20
                color: DrawerTheme.card
                Column {
                    id: savedCol
                    x: 18
                    y: 18
                    width: parent.width - 36
                    spacing: 14
                    Item {
                        width: parent.width
                        height: savedTitle.implicitHeight
                        BoussoleText {
                            id: savedTitle
                            text: card.modelData.title
                            font.pixelSize: 24
                            font.weight: Font.DemiBold
                        }
                        BoussoleText {
                            anchors.right: parent.right
                            anchors.baseline: savedTitle.baseline
                            text: card.modelData.left + root.b.tr(" min left", " min restantes")
                            color: DrawerTheme.secondary
                            font.pixelSize: 14
                        }
                    }
                    Column {
                        width: parent.width
                        spacing: 3
                        BoussoleText {
                            visible: !!card.modelData.file
                            width: parent.width
                            text: (card.modelData.file || "") + (card.modelData.page ? " · p. " + card.modelData.page : "")
                            font.pixelSize: 15
                            elide: Text.ElideRight
                        }
                        BoussoleText {
                            text: root.b.tr("saved ", "sauvegardée ") + card.modelData.since
                            color: DrawerTheme.secondary
                            font.pixelSize: 13
                        }
                    }
                    Row {
                        spacing: 8
                        BoussolePill {
                            primary: true
                            text: root.b.tr("Continue", "Continuer")
                            onClicked: root.b.resume(card.modelData.id)
                        }
                        BoussolePill {
                            text: root.b.tr("Close", "Clore")
                            onClicked: root.b.openClose(card.modelData.id)
                        }
                    }
                }
            }
        }
    }

    // ---- the programme slipping: one line ---------------------------------
    Rectangle {
        id: slip
        readonly property var short: (root.b.programme || {}).short || null
        visible: root.b.daemonConnected && slip.short !== null && !root.active
        width: parent.width
        height: 56
        radius: 20
        color: DrawerTheme.clear(DrawerTheme.card)
        border.width: 1
        border.color: "#ff9f5a"
        BoussoleText {
            x: 18
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - 36 - leversPill.width
            text: slip.short ? slip.short.domain + " · " + slip.short.margin + root.b.tr(" sessions before ", " séances avant le ") + slip.short.date : ""
            font.pixelSize: 14
            elide: Text.ElideRight
        }
        BoussolePill {
            id: leversPill
            anchors.right: parent.right
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            text: root.b.tr("Levers", "Leviers")
            onClicked: root.b.openProgramme("whatif")
        }
    }

    // ---- next, and a session now ------------------------------------------
    Column {
        visible: root.b.daemonConnected && !root.b.setupNeeded && !root.active
        width: parent.width
        spacing: 10
        Label { visible: root.next !== null; text: root.b.tr("Next", "Ensuite") }
        Rectangle {
            visible: root.next !== null
            width: parent.width
            height: nextCol.implicitHeight + 32
            radius: 20
            color: DrawerTheme.clear(DrawerTheme.card)
            border.width: 1
            border.color: DrawerTheme.faint
            Column {
                id: nextCol
                x: 18
                y: 16
                width: parent.width - 36
                spacing: 16
                Item {
                    width: parent.width
                    height: Math.max(nextText.implicitHeight, nextPills.height)
                    Column {
                        id: nextText
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 3
                        BoussoleText {
                            text: root.next ? root.next.title : ""
                            font.pixelSize: 17
                            font.weight: Font.DemiBold
                        }
                        BoussoleText {
                            text: root.next ? (root.next.date !== root.todayIso ? Qt.formatDate(new Date(root.next.date + "T12:00"), "ddd ") : "")
                                              + root.next.start + " · " + root.hm(root.minutes(root.next.start, root.next.end)) : ""
                            color: DrawerTheme.secondary
                            font.pixelSize: 13
                        }
                    }
                    Row {
                        id: nextPills
                        visible: !root.choosing
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 8
                        BoussolePill { text: root.b.tr("Later", "Plus tard"); onClicked: root.choosing = true }
                        BoussolePill { text: root.b.tr("Start", "Commencer"); onClicked: root.b.start(root.next.id) }
                    }
                }

                // Later, until: the nearest choices, or a time or a day typed.
                Column {
                    visible: root.choosing
                    width: parent.width
                    spacing: 8
                    Label { text: root.b.tr("Later, until", "Plus tard, jusqu'à") }
                    Grid {
                        id: choices
                        width: parent.width
                        columns: 2
                        spacing: 8
                        Repeater {
                            model: root.b.laterChoices
                            delegate: Rectangle {
                                id: choice
                                required property var modelData
                                width: (choices.width - choices.spacing) / 2
                                height: 44
                                radius: 14
                                color: choiceHit.containsMouse ? DrawerTheme.cardHover : DrawerTheme.clear(DrawerTheme.cardHover)
                                Behavior on color { ColorAnimation { duration: 120 } }
                                border.width: 1
                                border.color: DrawerTheme.faint
                                BoussoleText {
                                    anchors.left: parent.left
                                    anchors.leftMargin: 14
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: choice.modelData.label
                                    font.pixelSize: 14
                                }
                                BoussoleText {
                                    anchors.right: parent.right
                                    anchors.rightMargin: 14
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: String(choice.modelData.until).replace(/^(until|jusqu'à) /, "")
                                    color: DrawerTheme.muted
                                    font.pixelSize: 12
                                }
                                MouseArea {
                                    id: choiceHit
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        root.b.later(choice.modelData.id);
                                        root.choosing = false;
                                    }
                                }
                            }
                        }
                    }
                    BoussoleField {
                        id: typed
                        width: parent.width
                        placeholder: root.b.tr("A time or a day: 21:30, sun", "Une heure ou un jour : 21:30, dim")
                        onAccepted: {
                            if (typed.text.trim() === "") return;
                            root.b.later(typed.text.trim());
                            typed.text = "";
                            root.choosing = false;
                        }
                    }
                    BoussolePill {
                        text: root.b.tr("Cancel", "Annuler")
                        onClicked: root.choosing = false
                    }
                }
            }
        }

        // A session now, on what you choose: the most useful work first.
        Rectangle {
            width: parent.width
            height: 52
            radius: 20
            color: startHit.containsMouse ? DrawerTheme.cardHover : DrawerTheme.clear(DrawerTheme.cardHover)
            Behavior on color { ColorAnimation { duration: 120 } }
            border.width: 1
            border.color: DrawerTheme.faint
            BoussoleText {
                x: 18
                anchors.verticalCenter: parent.verticalCenter
                text: (root.starting ? "− " : "+ ") + root.b.tr("Start a session", "Lancer une séance")
                font.pixelSize: 15
                font.weight: Font.Medium
            }
            MouseArea {
                id: startHit
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.starting = !root.starting
            }
        }
        BoussoleFree {
            visible: root.starting
            width: parent.width
            span: root.b.nowFree ? root.b.nowFree.minutes : 0
            school: root.b.nowFree ? root.b.nowFree.school : false
            until: root.b.nowFree ? root.b.nowFree.until : ""
        }
    }

    // ---- the timetable at a glance: today's courses left, else the next day's
    Column {
        readonly property var c: root.b.status.courses || null
        visible: c !== null && c.rows.length > 0 && !root.starting
        width: parent.width
        spacing: 2
        Label { text: parent.c ? root.b.tr("Courses · ", "Cours · ") + parent.c.label : ""; bottomPadding: 6 }
        Repeater {
            model: parent.c ? parent.c.rows : []
            delegate: Item {
                required property var modelData
                width: root.width
                height: 36
                BoussoleText {
                    id: courseTime
                    anchors.verticalCenter: parent.verticalCenter
                    width: 92
                    text: modelData.start + "–" + modelData.end
                    color: modelData.now ? DrawerTheme.primary : DrawerTheme.secondary
                    font.pixelSize: 13
                    font.features: { "tnum": 1 }
                }
                BoussoleText {
                    anchors.left: courseTime.right
                    anchors.leftMargin: 14
                    anchors.right: courseRoom.left
                    anchors.rightMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    text: modelData.title
                    font.pixelSize: 15
                    font.weight: modelData.now ? Font.DemiBold : Font.Normal
                    wrapMode: Text.NoWrap
                    elide: Text.ElideRight
                }
                BoussoleText {
                    id: courseRoom
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: modelData.room
                    color: DrawerTheme.muted
                    font.pixelSize: 13
                }
            }
        }
    }

    // ---- coming up -----------------------------------------------------------
    Column {
        visible: (root.b.status.upcoming || []).length > 0 && !root.starting
        width: parent.width
        spacing: 2
        Label { text: root.b.tr("Coming up", "À venir"); bottomPadding: 6 }
        Repeater {
            model: root.b.status.upcoming || []
            delegate: Row {
                required property var modelData
                width: root.width
                height: 36
                spacing: 14
                BoussoleText {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 92
                    text: modelData.when
                    color: DrawerTheme.secondary
                    font.pixelSize: 13
                }
                BoussoleText {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - 92 - 70 - 28
                    text: modelData.title
                    font.pixelSize: 15
                    elide: Text.ElideRight
                }
                BoussoleText {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 70
                    horizontalAlignment: Text.AlignRight
                    text: modelData.len
                    color: DrawerTheme.muted
                    font.pixelSize: 13
                }
            }
        }
    }

    BoussoleText {
        visible: root.b.daemonConnected && !root.b.setupNeeded && root.next === null && !root.active && root.saved.length === 0
        width: parent.width
        text: root.b.paused ? root.b.tr("Paused.", "En pause.") : root.b.tr("Nothing planned.", "Rien de prévu.")
        color: DrawerTheme.secondary
    }
}
