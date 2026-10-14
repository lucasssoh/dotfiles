import QtQuick
import Quickshell
import Quickshell.Hyprland
import ".."          // ThinScrollBar
import "../../theme"
import "../../services"

// The room, in focus mode: fixed down the left edge of every study
// workspace (shell.qml). The module (or the project), the time left, the
// file put forward with its reason, then every file by chapter; Save &
// leave keeps the session for later, Close ends it.
Rectangle {
    id: root

    readonly property var b: BoussoleState
    readonly property var f: root.b.focus || ({})
    readonly property var t: root.b.tracking
    readonly property var r: root.b.room
    readonly property var doc: root.t && root.t.doc ? root.t.doc : null
    readonly property bool paused: root.t !== null && root.t.flags && root.t.flags.paused === true
    readonly property var current: (root.f.queue || []).find(q => q.state === "current") || null

    // Minutes to the planned end.
    function at(hm) {
        const d = new Date(root.b.nowMs);
        const p = (hm || "00:00").split(":");
        d.setHours(+p[0], +p[1], 0, 0);
        return d.getTime();
    }
    readonly property int minutesLeft: root.current ? Math.max(0, Math.round((root.at(root.current.end) - root.b.nowMs) / 60000)) : 0
    readonly property int length: root.current ? Math.round((root.at(root.current.end) - root.at(root.current.start)) / 60000) : 0
    function hm(m) {
        return m >= 60 ? Math.floor(m / 60) + " h" + (m % 60 ? " " + ("0" + (m % 60)).slice(-2) : "") : m + " min";
    }

    // The session's sheet closed: said to go on on paper, or not yet.
    readonly property bool paper: root.t !== null && root.t.paper === true
    readonly property bool sheetClosed: root.t !== null && root.doc === null && root.f.file === true && !root.paused

    readonly property var levels: [
        { id: "behind", en: "Behind", fr: "En retard" },
        { id: "shaky", en: "Unsure", fr: "Fragile" },
        { id: "fine", en: "Fine", fr: "À l'aise" },
        { id: "td-only", en: "Tutorials only", fr: "TD seulement" }
    ]
    readonly property var level: root.r && root.r.level ? root.levels.find(l => l.id === root.r.level) : null
    property bool levelOpen: false

    // Open by default: the chapter of the page on screen, else the one of
    // the file put forward. A touch opens or folds any.
    property var folded: ({})
    function holds(c, id) { return (c.items || []).some(i => i.id === id); }
    function isOpen(c) {
        if (root.folded[c.name] !== undefined) return root.folded[c.name] === false;
        const id = root.doc ? root.doc.item : (root.r && root.r.forward ? root.r.forward.id : "");
        return root.holds(c, id);
    }
    function toggle(c) {
        const f = Object.assign({}, root.folded);
        f[c.name] = root.isOpen(c);
        root.folded = f;
    }
    onRChanged: if (root.r && root.r.session !== root._roomOf) { root._roomOf = root.r.session; root.folded = ({}); root.levelOpen = false; }
    property string _roomOf: ""

    color: DrawerTheme.panelTop

    // The time left goes down paused or not, by the minute.
    Timer {
        interval: 15000
        repeat: true
        running: true
        onTriggered: root.b.nowMs = Date.now()
    }

    Flickable {
        id: flick
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: actions.top
        anchors.margins: 18
        anchors.bottomMargin: 12
        contentHeight: body.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
            id: body
            width: parent.width
            spacing: 18

            // The dimension's workspaces, the one you are on filled.
            Row {
                spacing: 6
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

            // ---- the module, its level and folder ------------------------
            Column {
                width: parent.width
                spacing: 4
                BoussoleText {
                    width: parent.width
                    text: root.r ? root.r.title : (root.f.title || "")
                    font.pixelSize: 24
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                }
                BoussoleText {
                    width: parent.width
                    text: !root.r ? ""
                        : root.r.kind !== "module" ? root.r.line
                        : (root.level ? root.b.tr(root.level.en, root.level.fr) + " · " : "") + root.r.dir
                    color: DrawerTheme.muted
                    font.pixelSize: 12
                    elide: Text.ElideRight
                    MouseArea {
                        anchors.fill: parent
                        enabled: root.r !== null && root.r.kind === "module"
                        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onClicked: root.levelOpen = !root.levelOpen
                    }
                }
                Flow {
                    visible: root.levelOpen
                    width: parent.width
                    spacing: 6
                    topPadding: 6
                    Repeater {
                        model: root.levels
                        delegate: BoussoleChip {
                            required property var modelData
                            text: root.b.tr(modelData.en, modelData.fr)
                            on: root.r !== null && root.r.level === modelData.id
                            onClicked: {
                                root.b.setLevel(root.r.id, modelData.id);
                                root.levelOpen = false;
                            }
                        }
                    }
                }
            }

            // ---- the time left ---------------------------------------------
            Row {
                spacing: 8
                BoussoleText {
                    anchors.baseline: leftOf.baseline
                    text: root.paused ? root.b.tr("Saved", "Sauvegardée") : String(root.minutesLeft)
                    font.pixelSize: 40
                    font.weight: Font.DemiBold
                    font.features: { "tnum": 1 }
                }
                BoussoleText {
                    id: leftOf
                    visible: !root.paused && root.length > 0
                    text: root.b.tr("min left of ", "min sur ") + root.hm(root.length)
                    color: DrawerTheme.secondary
                    font.pixelSize: 14
                }
            }

            // ---- put forward -------------------------------------------------
            Rectangle {
                visible: root.r !== null && root.r.forward !== null
                width: parent.width
                height: fwdCol.implicitHeight + 28
                radius: 16
                color: DrawerTheme.card
                Column {
                    id: fwdCol
                    x: 14
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - 28 - openPill.width - 10
                    spacing: 3
                    BoussoleText {
                        width: parent.width
                        text: root.r && root.r.forward ? root.b.tr("Up next · ", "À suivre · ") + root.r.forward.why : ""
                        color: DrawerTheme.secondary
                        font.pixelSize: 12
                        elide: Text.ElideRight
                    }
                    BoussoleText {
                        width: parent.width
                        text: root.r && root.r.forward ? (root.r.forward.num ? root.r.forward.num + " · " : "") + root.r.forward.title : ""
                        font.pixelSize: 15
                        font.weight: Font.DemiBold
                        wrapMode: Text.WordWrap
                        maximumLineCount: 2
                        elide: Text.ElideRight
                    }
                }
                BoussolePill {
                    id: openPill
                    anchors.right: parent.right
                    anchors.rightMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                    height: 34
                    primary: true
                    text: root.b.tr("Open", "Ouvrir")
                    onClicked: root.b.openItem(root.r.forward.id)
                }
            }

            // A campaign: its folder, wherever it is.
            BoussolePill {
                visible: root.r !== null && root.r.kind === "campaign" && root.r.line !== ""
                text: root.b.tr("Open the folder", "Ouvrir le dossier")
                onClicked: Quickshell.execDetached(["xdg-open", root.r.line])
            }

            // The sheet closed: closing ends nothing, the session goes on.
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
                        text: root.paper ? root.b.tr("On paper: the time counts.", "Sur papier : le temps compte.")
                                         : root.b.tr("The sheet is closed.", "La fiche est fermée.")
                        font.pixelSize: 13
                    }
                    Row {
                        spacing: 8
                        BoussolePill {
                            height: 34
                            text: root.b.tr("Open again", "Rouvrir")
                            onClicked: root.b.reopen()
                        }
                        BoussolePill {
                            visible: !root.paper
                            height: 34
                            text: root.b.tr("On paper", "Sur papier")
                            onClicked: root.b.onPaper()
                        }
                    }
                }
            }

            // ---- every file, by chapter --------------------------------------
            Column {
                width: parent.width
                spacing: 1
                Repeater {
                    model: root.r ? root.r.chapters : []
                    delegate: Column {
                        id: chap
                        required property var modelData
                        readonly property bool open: root.isOpen(chap.modelData) || chap.modelData.name === ""
                        width: parent.width
                        spacing: 1

                        Row {
                            visible: chap.modelData.name !== ""
                            width: parent.width
                            height: 32
                            spacing: 8
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                width: 14
                                text: "›"
                                rotation: chap.open ? 90 : 0
                                Behavior on rotation { NumberAnimation { duration: 140 } }
                                horizontalAlignment: Text.AlignHCenter
                                color: DrawerTheme.muted
                                font.family: Fonts.ui
                                font.pixelSize: 16
                            }
                            BoussoleText {
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width - 22 - chapCount.implicitWidth - 8
                                text: chap.modelData.name
                                font.pixelSize: 14
                                font.weight: Font.Medium
                                elide: Text.ElideRight
                            }
                            BoussoleText {
                                id: chapCount
                                anchors.verticalCenter: parent.verticalCenter
                                text: chap.modelData.count
                                color: DrawerTheme.muted
                                font.pixelSize: 12
                            }
                            MouseArea {
                                width: parent.width
                                height: parent.height
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.toggle(chap.modelData)
                            }
                        }

                        Repeater {
                            model: chap.open ? chap.modelData.items : []
                            delegate: Rectangle {
                                id: file
                                required property var modelData
                                readonly property bool onScreen: root.doc !== null && root.doc.item === file.modelData.id
                                readonly property bool read: file.modelData.state === "read"
                                readonly property bool going: file.modelData.state === "progress" || file.onScreen
                                width: chap.width
                                height: 32
                                radius: 10
                                color: file.onScreen ? DrawerTheme.card : (fileHit.containsMouse ? DrawerTheme.cardHover : DrawerTheme.clear(DrawerTheme.cardHover))
                                Behavior on color { ColorAnimation { duration: 120 } }

                                // ✓ read · ● under way · ○ not yet
                                Rectangle {
                                    id: mark
                                    x: chap.modelData.name !== "" ? 24 : 6
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 8
                                    height: 8
                                    radius: 4
                                    visible: !file.read
                                    color: file.going ? DrawerTheme.primary : DrawerTheme.clear(DrawerTheme.primary)
                                    border.width: file.going ? 0 : 1.5
                                    border.color: DrawerTheme.faint
                                }
                                BoussoleText {
                                    visible: file.read
                                    anchors.horizontalCenter: mark.horizontalCenter
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "✓"
                                    color: DrawerTheme.secondary
                                    font.pixelSize: 12
                                }
                                BoussoleText {
                                    anchors.left: mark.right
                                    anchors.leftMargin: 10
                                    anchors.right: fileMeta.left
                                    anchors.rightMargin: 8
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: (file.modelData.num ? file.modelData.num + " " : "") + String(file.modelData.title).replace(/^Séance( TP\d)? — /, "")
                                    color: file.read ? DrawerTheme.secondary : DrawerTheme.primary
                                    font.pixelSize: 13
                                    font.weight: file.onScreen ? Font.DemiBold : Font.Normal
                                    wrapMode: Text.NoWrap
                                    elide: Text.ElideRight
                                }
                                BoussoleText {
                                    id: fileMeta
                                    anchors.right: parent.right
                                    anchors.rightMargin: 8
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: file.onScreen && root.doc.pages > 0 ? "p. " + root.doc.page
                                        : file.modelData.state === "progress" ? file.modelData.detail : ""
                                    color: DrawerTheme.muted
                                    font.pixelSize: 12
                                }
                                MouseArea {
                                    id: fileHit
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.b.openItem(file.modelData.id)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    ThinScrollBar {
        target: flick
        anchors.left: flick.right
        anchors.leftMargin: 4
        anchors.top: flick.top
        anchors.bottom: flick.bottom
    }

    // ---- Save & leave, Close ---------------------------------------------
    Row {
        id: actions
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: 18
        spacing: 8
        BoussolePill {
            width: (parent.width - 8) / 2
            text: root.paused ? root.b.tr("Continue", "Continuer") : root.b.tr("Save & leave", "Sauver, partir")
            onClicked: root.paused ? root.b.resumeSession() : root.b.pauseSession()
        }
        BoussolePill {
            width: (parent.width - 8) / 2
            text: root.b.tr("Close", "Clore")
            onClicked: if (root.t) root.b.openClose(root.t.session, Quickshell.screens[0])
        }
    }
}
