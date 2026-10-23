import QtQuick
import "../../theme"
import "../../services"

// Subjects: where you stand in each (behind gets more time, tutorials
// only gets no sessions of its own) and what its sessions open. "Boussole"
// runs `boussole open {folder} --resume`; any other command can be typed,
// {folder} standing for the subject's folder.
Column {
    id: root

    spacing: 12
    readonly property var b: BoussoleState
    readonly property var domains: (root.b.settings.domains || []).filter(d => !d.archived)
    readonly property string boussole: "boussole open {folder} --resume"
    readonly property var levels: [
        { id: "behind", label: root.b.tr("Behind", "En retard") },
        { id: "shaky", label: root.b.tr("Shaky", "Fragile") },
        { id: "fine", label: root.b.tr("Fine", "Ça va") },
        { id: "td-only", label: root.b.tr("Tutorials only", "TD seulement") }
    ]

    // One subject's fields changed, the others kept.
    function patch(id, change) {
        const list = (root.b.settings.domains || []).map(d => d.id === id ? Object.assign({}, d, change) : d);
        root.b.setSettings({ domains: list });
    }

    BoussoleText {
        text: root.b.tr("Subjects", "Modules")
        font.pixelSize: 18
        font.weight: Font.Bold
    }

    Repeater {
        model: root.domains
        delegate: Rectangle {
            id: card
            required property var modelData
            readonly property string launch: modelData.launch || ""
            width: root.width
            height: col.implicitHeight + 28
            radius: 14
            color: DrawerTheme.card
            Column {
                id: col
                x: 14
                y: 14
                width: parent.width - 28
                spacing: 8
                BoussoleText { text: card.modelData.id; font.weight: Font.Bold }
                Flow {
                    width: parent.width
                    spacing: 6
                    Repeater {
                        model: root.levels
                        delegate: BoussoleChip {
                            required property var modelData
                            text: modelData.label
                            on: (card.modelData.level || "fine") === modelData.id
                            onClicked: root.patch(card.modelData.id, { level: modelData.id })
                        }
                    }
                }
                Flow {
                    width: parent.width
                    spacing: 6
                    BoussoleChip {
                        text: root.b.tr("Nothing opens", "Rien ne s'ouvre")
                        on: card.launch === ""
                        onClicked: root.patch(card.modelData.id, { launch: null })
                    }
                    BoussoleChip {
                        text: "Boussole"
                        on: card.launch === root.boussole
                        onClicked: root.patch(card.modelData.id, { launch: root.boussole })
                    }
                    BoussoleChip {
                        text: root.b.tr("A command", "Une commande")
                        on: card.launch !== "" && card.launch !== root.boussole
                        onClicked: command.visible = true
                    }
                }
                BoussoleField {
                    id: command
                    visible: card.launch !== "" && card.launch !== root.boussole
                    text: card.launch
                    placeholder: "liseuse {folder}/00_Index.md"
                    onAccepted: root.patch(card.modelData.id, { launch: command.text.trim() === "" ? null : command.text.trim() })
                }
            }
        }
    }

    BoussoleText {
        width: parent.width
        text: root.b.tr("A session with something to open counts its time while Boussole is in front; notifications keep quiet there and show anywhere else.",
                        "Une séance qui ouvre quelque chose compte son temps tant que Boussole est devant ; les notifications s'y taisent et s'affichent partout ailleurs.")
        color: DrawerTheme.secondary
        font.pixelSize: 12
    }
}
