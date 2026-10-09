import QtQuick
import Quickshell
import Quickshell.Hyprland
import "../../theme"
import "../../services"

// The session's panel, in focus mode: fixed down the left edge of every
// study workspace (shell.qml). The dimension's workspaces, the time left,
// the objective, the page Liseuse shows, the evening's files, and Next,
// Pause, Close. On the last page of the file, the next one is offered;
// moving on declares nothing, Close still confirms.
Rectangle {
    id: root

    readonly property var b: BoussoleState
    readonly property var f: root.b.focus || ({})
    readonly property var t: root.b.tracking
    readonly property var doc: root.t && root.t.doc ? root.t.doc : null
    readonly property bool paused: root.t !== null && root.t.flags && root.t.flags.paused === true
    readonly property var queue: root.f.queue || []
    readonly property var current: root.queue.find(q => q.state === "current") || null
    readonly property var nextItem: root.queue.find(q => q.session === root.f.next) || null

    // Minutes to the planned end, and the share of the slot gone by.
    function at(hm) {
        const d = new Date(root.b.nowMs);
        const p = (hm || "00:00").split(":");
        d.setHours(+p[0], +p[1], 0, 0);
        return d.getTime();
    }
    readonly property int secondsLeft: root.current ? Math.max(0, Math.round((root.at(root.current.end) - root.b.nowMs) / 1000)) : 0
    readonly property real spent: {
        if (!root.current) return 0;
        const a = root.at(root.current.start), z = root.at(root.current.end);
        return z > a ? Math.min(1, Math.max(0, (root.b.nowMs - a) / (z - a))) : 0;
    }
    // The session's sheet closed: said to go on on paper, or not yet.
    readonly property bool hasFile: root.f.file === true
    readonly property bool paper: root.t !== null && root.t.paper === true
    readonly property bool sheetClosed: root.t !== null && root.doc === null && root.hasFile && !root.paused
    readonly property bool lastPage: root.doc !== null && root.doc.pages > 0 && root.doc.page >= root.doc.pages

    color: DrawerTheme.panelTop

    // The bar's clock only ticks while time counts: this one ticks for the
    // time left, which goes down paused or not, by the second.
    Timer {
        interval: 1000
        repeat: true
        running: true
        onTriggered: root.b.nowMs = Date.now()
    }

    Flickable {
        anchors.fill: parent
        anchors.margins: 18
        contentHeight: body.implicitHeight
        clip: true

        Column {
            id: body
            width: parent.width
            spacing: 16

            // The dimension's workspaces, the one you are on filled.
            Row {
                spacing: 6
                BoussoleText {
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.b.tr("Study", "Étude")
                    color: DrawerTheme.secondary
                    font.pixelSize: 12
                    font.weight: Font.Bold
                }
                Repeater {
                    model: root.b.studyLast - root.b.studyFirst + 1
                    delegate: BoussoleChip {
                        required property int index
                        readonly property int ws: root.b.studyFirst + index
                        text: String(index + 1)
                        on: Hyprland.focusedWorkspace !== null && Hyprland.focusedWorkspace.id === ws
                        onClicked: root.b.goStudy(ws)
                    }
                }
            }

            Column {
                width: parent.width
                spacing: 2
                BoussoleText {
                    width: parent.width
                    text: root.f.title || ""
                    color: DrawerTheme.secondary
                    font.pixelSize: 13
                    elide: Text.ElideRight
                }
                BoussoleText {
                    text: root.paused ? root.b.tr("Paused", "En pause") : root.b.clock(root.secondsLeft)
                    font.pixelSize: 40
                    font.weight: Font.Bold
                    font.features: { "tnum": 1 }
                }
                BoussoleText {
                    text: root.current ? root.b.tr("left · until ", "restantes · jusqu'à ") + root.current.end : ""
                    color: DrawerTheme.secondary
                    font.pixelSize: 12
                }
            }

            Rectangle {
                width: parent.width
                height: 4
                radius: 2
                color: DrawerTheme.cardRaised
                Rectangle {
                    width: parent.width * root.spent
                    height: parent.height
                    radius: 2
                    color: DrawerTheme.primary
                }
            }

            BoussoleText {
                width: parent.width
                visible: text !== ""
                text: root.f.objective ? root.b.tr("Objective: ", "Objectif : ") + root.f.objective : ""
                color: DrawerTheme.primary
                wrapMode: Text.WordWrap
                font.pixelSize: 13
            }

            // The sheet closed: closing ends nothing, so the session goes
            // on; say how, or open it again.
            BoussolePop {
                shown: root.sheetClosed
                width: parent.width
                height: closedCol.implicitHeight + 24
                radius: 16
                color: DrawerTheme.card
                border.width: 1
                border.color: DrawerTheme.faint
                Column {
                    id: closedCol
                    x: 12
                    y: 12
                    width: parent.width - 24
                    spacing: 8
                    BoussoleText {
                        text: root.paper ? root.b.tr("ON PAPER", "SUR PAPIER") : root.b.tr("SHEET CLOSED", "FICHE FERMÉE")
                        color: DrawerTheme.secondary
                        font.pixelSize: 11
                        font.weight: Font.Bold
                        font.letterSpacing: 1
                    }
                    BoussoleText {
                        width: parent.width
                        text: root.paper
                              ? root.b.tr("The time counts; nothing is asked until the sheet is back.",
                                          "Le temps compte ; rien n'est demandé jusqu'au retour de la fiche.")
                              : root.b.tr("The session goes on. Open it again, or go on on paper.",
                                          "La séance continue. Rouvre-la, ou continue sur papier.")
                        color: DrawerTheme.secondary
                        font.pixelSize: 12
                    }
                    BoussolePill {
                        width: parent.width
                        primary: true
                        text: root.b.tr("Open the sheet again", "Rouvrir la fiche")
                        onClicked: root.b.reopen()
                    }
                    BoussolePill {
                        visible: !root.paper
                        width: parent.width
                        text: root.b.tr("On paper", "Sur papier")
                        onClicked: root.b.onPaper()
                    }
                }
            }

            // Nothing to read in this session (a tutorial to prepare):
            // Liseuse's picker, which opens on this workspace.
            BoussolePill {
                visible: root.doc === null && !root.hasFile
                width: parent.width
                text: root.b.tr("Open a file", "Ouvrir un fichier")
                onClicked: Quickshell.execDetached([Quickshell.env("HOME") + "/.local/bin/liseuse", "pick"])
            }

            BoussoleText {
                visible: root.doc !== null
                text: root.doc ? root.b.tr("Page ", "Page ") + root.doc.page + root.b.tr(" of ", " sur ") + root.doc.pages
                                 + (root.doc.section ? " · §" + root.doc.section : "") : ""
                color: DrawerTheme.secondary
                font.pixelSize: 12
            }

            // The last page: what comes next.
            BoussolePop {
                shown: root.lastPage && root.nextItem !== null
                width: parent.width
                height: lastCol.implicitHeight + 24
                radius: 16
                color: DrawerTheme.card
                border.width: 1
                border.color: DrawerTheme.faint
                Column {
                    id: lastCol
                    x: 12
                    y: 12
                    width: parent.width - 24
                    spacing: 6
                    BoussoleText {
                        text: root.b.tr("LAST PAGE", "DERNIÈRE PAGE")
                        color: DrawerTheme.secondary
                        font.pixelSize: 11
                        font.weight: Font.Bold
                        font.letterSpacing: 1
                    }
                    BoussoleText {
                        width: parent.width
                        text: root.nextItem ? root.b.tr("Next: ", "Suivant : ") + root.nextItem.title : ""
                        wrapMode: Text.WordWrap
                        font.pixelSize: 14
                        font.weight: Font.DemiBold
                    }
                    BoussoleText {
                        width: parent.width
                        text: root.b.tr("Moving on declares nothing: you confirm what was done at Close.",
                                        "Passer au suivant ne déclare rien : tu confirmes ce qui est fait à Clore.")
                        color: DrawerTheme.secondary
                        wrapMode: Text.WordWrap
                        font.pixelSize: 12
                    }
                }
            }

            BoussoleText {
                visible: root.queue.length > 1
                text: root.b.tr("THIS EVENING", "CE SOIR")
                color: DrawerTheme.secondary
                font.pixelSize: 11
                font.weight: Font.Bold
                font.letterSpacing: 1
            }
            Column {
                visible: root.queue.length > 1
                width: parent.width
                spacing: 4
                Repeater {
                    model: root.queue
                    delegate: Rectangle {
                        required property var modelData
                        required property int index
                        readonly property bool cur: modelData.state === "current"
                        width: parent.width
                        height: Math.max(44, row.implicitHeight + 16)
                        radius: 12
                        color: cur ? DrawerTheme.card : "transparent"
                        Behavior on color { ColorAnimation { duration: 160 } }
                        border.width: cur ? 1 : 0
                        border.color: DrawerTheme.faint
                        Row {
                            id: row
                            x: 10
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - 20
                            spacing: 10
                            Rectangle {
                                width: 22
                                height: 22
                                radius: 7
                                anchors.verticalCenter: parent.verticalCenter
                                color: cur ? DrawerTheme.on : DrawerTheme.cardRaised
                                BoussoleText {
                                    anchors.centerIn: parent
                                    text: modelData.state === "done" ? "✓" : String(index + 1)
                                    color: cur ? DrawerTheme.onInk : DrawerTheme.primary
                                    font.pixelSize: 11
                                    font.weight: Font.Bold
                                }
                            }
                            BoussoleText {
                                width: parent.width - 32
                                anchors.verticalCenter: parent.verticalCenter
                                text: modelData.title
                                color: cur ? DrawerTheme.primary : (modelData.state === "done" ? DrawerTheme.muted : DrawerTheme.secondary)
                                wrapMode: Text.WordWrap
                                font.pixelSize: 13
                                font.weight: Font.DemiBold
                            }
                        }
                    }
                }
            }

            Column {
                width: parent.width
                spacing: 8
                BoussolePill {
                    visible: root.f.next !== null && root.f.next !== undefined
                    width: parent.width
                    primary: true
                    text: root.b.tr("Next file", "Fichier suivant")
                    onClicked: root.b.nextFile(Quickshell.screens[0])
                }
                Row {
                    width: parent.width
                    spacing: 8
                    BoussolePill {
                        width: (parent.width - 8) / 2
                        text: root.paused ? root.b.tr("Resume", "Reprendre") : root.b.tr("Pause", "Pause")
                        onClicked: root.paused ? root.b.resumeSession() : root.b.pauseSession()
                    }
                    BoussolePill {
                        width: (parent.width - 8) / 2
                        primary: !root.f.next
                        text: root.b.tr("Close", "Clore")
                        onClicked: if (root.t) root.b.openClose(root.t.session, Quickshell.screens[0])
                    }
                }
            }
        }
    }
}
