import QtQuick
import "../../theme"
import "../../services"

// Exams and hand-ins: those from the timetable and those added here. A
// line is read as quick add does, and what it understood, with its effect
// on the plan, is shown before anything is kept.
Column {
    id: root

    spacing: 12
    readonly property var b: BoussoleState
    property string seen: ""
    property bool understood: false

    readonly property var list: root.b.deadlines.slice().sort((x, y) => x.at < y.at ? -1 : 1)

    BoussoleText {
        text: root.b.tr("Exams and hand-ins", "Examens et rendus")
        font.pixelSize: 18
        font.weight: Font.Bold
    }

    BoussoleField {
        id: line
        placeholder: root.b.tr("exam L&MC 18/12 · test OC 12/11 14h · due ARGOS 12/11 30h", "examen L&MC 18/12 · cc OC 12/11 14h · rendu ARGOS 12/11 30h")
        onAccepted: root.b.addLine(line.text, false, (r) => {
            root.seen = r.text || "";
            root.understood = r.ok && r.data && r.data.understood === true;
        })
    }
    BoussoleText {
        visible: root.seen !== ""
        width: parent.width
        text: root.seen
        color: root.understood ? DrawerTheme.primary : DrawerTheme.danger
        font.pixelSize: 13
    }
    Row {
        visible: root.understood
        spacing: 8
        BoussolePill {
            primary: true
            text: root.b.tr("Add", "Ajouter")
            onClicked: root.b.addLine(line.text, true, () => {
                line.text = "";
                root.seen = "";
                root.understood = false;
            })
        }
        BoussolePill {
            text: root.b.tr("Cancel", "Annuler")
            onClicked: {
                root.seen = "";
                root.understood = false;
            }
        }
    }
    BoussoleText {
        visible: root.seen === ""
        width: parent.width
        text: root.b.tr("Enter shows what was understood, and what it moves, before anything is kept.",
                        "Entrée montre ce qui a été compris, et ce que ça déplace, avant de garder quoi que ce soit.")
        color: DrawerTheme.secondary
        font.pixelSize: 12
    }

    Repeater {
        model: root.list
        delegate: Rectangle {
            id: dl
            required property var modelData
            readonly property var d: modelData
            width: root.width
            height: 54
            radius: 12
            color: "transparent"
            border.width: 1
            border.color: DrawerTheme.faint
            opacity: new Date(d.at) < new Date() ? 0.5 : 1
            Column {
                x: 14
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - 120
                BoussoleText { width: parent.width; text: dl.d.title; font.weight: Font.Bold; elide: Text.ElideRight; wrapMode: Text.NoWrap }
                BoussoleText {
                    width: parent.width
                    text: new Date(dl.d.at).toLocaleString(Qt.locale(root.b.fr ? "fr_FR" : "en_US"), root.b.fr ? "ddd d MMM · HH:mm" : "ddd MMM d · HH:mm")
                          + (dl.d.hours ? " · " + dl.d.hours + " h" : "")
                    color: DrawerTheme.secondary
                    font.pixelSize: 12
                }
            }
            BoussoleText {
                visible: dl.d.source === "calendar"
                anchors.verticalCenter: parent.verticalCenter
                anchors.right: parent.right
                anchors.rightMargin: 14
                text: "ADE"
                color: DrawerTheme.secondary
                font.pixelSize: 12
                font.weight: Font.Bold
            }
            BoussoleChip {
                visible: dl.d.source !== "calendar"
                anchors.verticalCenter: parent.verticalCenter
                anchors.right: parent.right
                anchors.rightMargin: 10
                text: root.b.tr("Remove", "Retirer")
                onClicked: root.b.send({ cmd: "deadline-remove", id: dl.d.id })
            }
        }
    }
}
