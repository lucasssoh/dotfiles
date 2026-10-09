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
                BoussoleText {
                    text: root.b.tr("Where you stand", "Où tu en es")
                    color: DrawerTheme.secondary
                    font.pixelSize: 12
                }
                Flow {
                    width: parent.width
                    spacing: 6
                    Repeater {
                        model: [
                            { id: "behind", en: "Behind", fr: "En retard" },
                            { id: "shaky", en: "Unsure", fr: "Moyen" },
                            { id: "fine", en: "Fine", fr: "À l'aise" },
                            { id: "td-only", en: "Tutorials only", fr: "TD seulement" }
                        ]
                        delegate: BoussoleChip {
                            required property var modelData
                            text: root.b.tr(modelData.en, modelData.fr)
                            on: (dom.d.level || "fine") === modelData.id
                            onClicked: root.save(dom.d.id, d => d.level = modelData.id)
                        }
                    }
                }
                BoussoleText {
                    width: parent.width
                    wrapMode: Text.WordWrap
                    color: DrawerTheme.secondary
                    font.pixelSize: 12
                    text: (dom.d.level || "fine") === "behind"
                        ? root.b.tr("More time per sheet, and it goes first.", "Plus de temps par fiche, et elle passe devant.")
                        : (dom.d.level === "td-only"
                            ? root.b.tr("Nothing to read: tutorials, projects and exams only.", "Rien à lire : seulement les TD, les projets et les examens.")
                            : "")
                    visible: text !== ""
                }
                Flow {
                    width: parent.width
                    spacing: 6
                    BoussoleChip {
                        text: root.b.tr("Spaced reviews", "Révisions espacées")
                        on: dom.d.spaced === true
                        onClicked: root.save(dom.d.id, d => d.spaced = !d.spaced)
                    }
                }
                // How fast its sheets go, over the planner's estimate
                // (the setting's pace.domain_factor): what was guessed, until
                // closed sessions measure it.
                Flow {
                    width: parent.width
                    spacing: 6
                    readonly property real factor: ((root.b.settings.pace || {}).domain_factor || {})[dom.d.id] || 0
                    BoussoleText {
                        text: root.b.tr("Sheets", "Fiches")
                        color: DrawerTheme.secondary
                        font.pixelSize: 12
                        height: 32
                        verticalAlignment: Text.AlignVCenter
                    }
                    Repeater {
                        model: [
                            { f: 0.5, label: root.b.tr("quick", "rapides") },
                            { f: 0, label: root.b.tr("as estimated", "comme estimé") },
                            { f: 1.5, label: root.b.tr("long", "longues") }
                        ]
                        delegate: BoussoleChip {
                            required property var modelData
                            text: modelData.label
                            on: parent.factor === modelData.f
                            onClicked: {
                                const patch = { pace: { domain_factor: {} } };
                                patch.pace.domain_factor[dom.d.id] = modelData.f === 0 ? null : modelData.f;
                                root.b.setSettings(patch);
                            }
                        }
                    }
                }
                Flow {
                    width: parent.width
                    spacing: 6
                    // A course subject: sheets are lessons, read and
                    // recalled; the exercises live in the exercise files,
                    // tutorials and exam subjects.
                    BoussoleChip {
                        text: root.b.tr("Lessons: sheets read only", "Cours : fiches lues seulement")
                        on: dom.d.lessons === true
                        onClicked: root.save(dom.d.id, d => d.lessons = !d.lessons)
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
