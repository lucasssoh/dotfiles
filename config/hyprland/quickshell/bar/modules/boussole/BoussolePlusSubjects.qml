import QtQuick
import "../../theme"
import "../../services"

// Subjects: one per course folder. Each one's names in the timetable
// (several allowed, separated by |), spaced reviews, and archiving, which
// keeps its progress but gives it no more sessions.
Column {
    id: root

    spacing: 12
    readonly property var b: BoussoleState
    readonly property var domains: root.b.settings.domains || []

    function save(id, change) {
        const list = JSON.parse(JSON.stringify(root.domains));
        let d = list.find(x => x.id === id);
        if (!d) { d = { id: id, spaced: true, calendar_names: [] }; list.push(d); }
        change(d);
        root.b.setSettings({ domains: list });
    }

    BoussoleText {
        text: root.b.tr("Subjects", "Matières")
        font.pixelSize: 18
        font.weight: Font.Bold
    }

    Repeater {
        model: root.domains
        delegate: Rectangle {
            id: dom
            required property var modelData
            readonly property var d: modelData
            width: root.width
            height: domCol.implicitHeight + 24
            radius: 14
            color: "transparent"
            border.width: 1
            border.color: DrawerTheme.faint
            opacity: d.archived ? 0.6 : 1
            Column {
                id: domCol
                x: 14
                y: 12
                width: parent.width - 28
                spacing: 8
                BoussoleText { text: dom.d.id; font.pixelSize: 16; font.weight: Font.Bold }
                BoussoleText {
                    text: root.b.tr("Its courses in the timetable", "Ses cours dans l'emploi du temps")
                    color: DrawerTheme.secondary
                    font.pixelSize: 12
                }
                BoussoleField {
                    id: names
                    width: parent.width
                    text: (dom.d.calendar_names || []).join(" | ")
                    placeholder: root.b.tr("Course name in ADE, then Enter", "Nom du cours dans ADE, puis Entrée")
                    onAccepted: root.save(dom.d.id, d => d.calendar_names = names.text.split("|").map(x => x.trim()).filter(x => x !== ""))
                }
                Flow {
                    width: parent.width
                    spacing: 6
                    BoussoleChip {
                        text: root.b.tr("Spaced reviews", "Révisions espacées")
                        on: dom.d.spaced === true
                        onClicked: root.save(dom.d.id, d => d.spaced = !d.spaced)
                    }
                    BoussoleChip {
                        text: dom.d.archived ? root.b.tr("Archived · restore", "Archivée · rétablir") : root.b.tr("Archive", "Archiver")
                        onClicked: root.save(dom.d.id, d => d.archived = !d.archived)
                    }
                }
            }
        }
    }

    BoussoleField {
        id: added
        placeholder: root.b.tr("Add a subject: its folder's name, then Enter", "Ajouter une matière : le nom de son dossier, puis Entrée")
        onAccepted: {
            if (added.text.trim() === "") return;
            root.save(added.text.trim(), d => {});
            added.text = "";
        }
    }
}
