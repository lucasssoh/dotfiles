import QtQuick
import "../../theme"
import "../../services"

// Files: the new ones first, waiting for a decision (nothing is planned
// before the user says so), then every file by subject. A subject's list
// opens when touched; each file says what was decided and when it comes.
Column {
    id: root

    spacing: 14
    readonly property var b: BoussoleState
    readonly property var f: b.files
    property string openDomain: ""

    component Section: BoussoleText {
        color: DrawerTheme.secondary
        font.pixelSize: 11
        font.weight: Font.Bold
        font.letterSpacing: 1
        font.capitalization: Font.AllUppercase
    }

    component Badge: Rectangle {
        property string text: ""
        width: 54
        height: 22
        radius: 7
        color: DrawerTheme.cardRaised
        BoussoleText {
            anchors.centerIn: parent
            text: parent.text
            font.pixelSize: 10
            font.weight: Font.Bold
            color: DrawerTheme.secondary
        }
    }

    BoussoleText {
        visible: root.f === null
        text: "…"
        color: DrawerTheme.secondary
    }

    BoussoleText {
        visible: root.f !== null
        width: parent.width
        text: root.f ? (root.f.root || "") + " · " + root.f.count + root.b.tr(" files", " fichiers") : ""
        color: DrawerTheme.secondary
        font.pixelSize: 13
    }

    // ---- new ------------------------------------------------------------------
    Section {
        visible: root.f !== null && root.f.undecided.length > 0
        text: root.b.tr("New · to plan (", "Nouveaux · à planifier (") + (root.f ? root.f.undecided.length : 0) + ")"
    }
    Flow {
        visible: root.f !== null && root.f.undecided.length > 1
        width: parent.width
        spacing: 8
        BoussolePill {
            text: root.b.tr("Plan all", "Tout planifier")
            onClicked: root.b.decide(root.f.undecided.map(i => i.id), "planned")
        }
        BoussolePill {
            text: root.b.tr("Ignore all", "Tout ignorer")
            onClicked: root.b.decide(root.f.undecided.map(i => i.id), "ignored")
        }
    }
    Repeater {
        model: root.f ? root.f.undecided : []
        delegate: Rectangle {
            id: fresh
            required property var modelData
            width: root.width
            height: freshCol.implicitHeight + 24
            radius: 14
            color: DrawerTheme.card
            Column {
                id: freshCol
                x: 12
                y: 12
                width: parent.width - 24
                spacing: 8
                Row {
                    spacing: 10
                    width: parent.width
                    Badge { text: fresh.modelData.kind }
                    Column {
                        width: parent.width - 64
                        BoussoleText { width: parent.width; text: fresh.modelData.title + (fresh.modelData.star ? " ★" : ""); font.weight: Font.Bold }
                        BoussoleText { width: parent.width; text: fresh.modelData.dir; color: DrawerTheme.secondary; font.pixelSize: 12 }
                    }
                }
                Row {
                    spacing: 8
                    BoussoleChip { text: root.b.tr("Plan", "Planifier"); onClicked: root.b.decide([fresh.modelData.id], "planned") }
                    BoussoleChip { text: root.b.tr("Ignore", "Ignorer"); onClicked: root.b.decide([fresh.modelData.id], "ignored") }
                }
            }
        }
    }

    // ---- all ------------------------------------------------------------------
    Section {
        visible: root.f !== null
        text: root.b.tr("All files", "Tous les fichiers")
    }
    Repeater {
        model: root.f ? root.f.domains : []
        delegate: Column {
            id: dom
            required property var modelData
            readonly property bool open: root.openDomain === modelData.domain
            width: root.width
            spacing: 6

            Rectangle {
                width: parent.width
                height: 40
                radius: 12
                color: domHit.containsMouse ? DrawerTheme.cardHover : "transparent"
                border.width: 1
                border.color: DrawerTheme.faint
                BoussoleText {
                    anchors.verticalCenter: parent.verticalCenter
                    x: 14
                    text: (dom.open ? "▾  " : "▸  ") + dom.modelData.domain
                    font.weight: Font.Bold
                }
                BoussoleText {
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.right: parent.right
                    anchors.rightMargin: 14
                    text: dom.modelData.items.filter(i => i.inclusion === "planned").length + " / " + dom.modelData.items.length
                    color: DrawerTheme.secondary
                    font.pixelSize: 13
                }
                MouseArea {
                    id: domHit
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.openDomain = dom.open ? "" : dom.modelData.domain
                }
            }

            Repeater {
                model: dom.open ? dom.modelData.items : []
                delegate: Row {
                    id: file
                    required property var modelData
                    readonly property var i: modelData
                    width: dom.width
                    spacing: 10
                    leftPadding: 6
                    Badge { anchors.verticalCenter: parent.verticalCenter; text: file.i.kind }
                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - 54 - 110 - 26
                        BoussoleText { width: parent.width; text: file.i.title + (file.i.star ? " ★" : ""); font.pixelSize: 13; elide: Text.ElideRight; wrapMode: Text.NoWrap }
                        BoussoleText {
                            width: parent.width
                            text: file.i.done ? root.b.tr("done", "fait")
                                : file.i.inclusion === "ignored" ? root.b.tr("ignored", "ignoré")
                                : file.i.inclusion === "planned" ? (file.i.next ? root.b.tr("next: ", "prochaine : ") + file.i.next : root.b.tr("planned, past the horizon", "planifié, au-delà de l'horizon"))
                                : root.b.tr("to decide", "à décider")
                            color: DrawerTheme.secondary
                            font.pixelSize: 12
                        }
                    }
                    BoussoleChip {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 110
                        text: file.i.inclusion === "planned" ? root.b.tr("Planned", "Planifié") : root.b.tr("Plan", "Planifier")
                        on: file.i.inclusion === "planned"
                        onClicked: root.b.decide([file.i.id], file.i.inclusion === "planned" ? "ignored" : "planned")
                    }
                }
            }
        }
    }
}
