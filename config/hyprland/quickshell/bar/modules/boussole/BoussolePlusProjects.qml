import QtQuick
import "../../theme"
import "../../services"

// Projects: each one's steps, ticked off as they are done, and a short
// form for a new one. Hours are the user's guess; the plan corrects them
// with the measured bias.
Column {
    id: root

    spacing: 12
    readonly property var b: BoussoleState
    property string error: ""

    BoussoleText {
        text: root.b.tr("Projects", "Projets")
        font.pixelSize: 18
        font.weight: Font.Bold
    }

    Repeater {
        model: root.b.projects
        delegate: Rectangle {
            id: proj
            required property var modelData
            readonly property var p: modelData
            width: root.width
            height: projCol.implicitHeight + 24
            radius: 14
            color: "transparent"
            border.width: 1
            border.color: DrawerTheme.faint
            Column {
                id: projCol
                x: 14
                y: 12
                width: parent.width - 28
                spacing: 8
                BoussoleText {
                    width: parent.width
                    text: proj.p.name + (proj.p.domain ? " · " + proj.p.domain : "")
                    font.weight: Font.Bold
                }
                BoussoleText {
                    width: parent.width
                    text: root.b.tr("Due ", "À rendre le ") + new Date(proj.p.due).toLocaleDateString(Qt.locale(root.b.fr ? "fr_FR" : "en_US"), root.b.fr ? "ddd d MMM" : "ddd MMM d")
                          + root.b.tr(", finished 3 days before", ", fini 3 jours avant")
                    color: DrawerTheme.secondary
                    font.pixelSize: 13
                }
                Flow {
                    width: parent.width
                    spacing: 6
                    Repeater {
                        model: proj.p.steps
                        delegate: BoussoleChip {
                            required property var modelData
                            required property int index
                            text: (modelData.done ? "✓ " : "") + modelData.name + " · " + modelData.hours + " h"
                            on: modelData.done === true
                            onClicked: {
                                const p = JSON.parse(JSON.stringify(proj.p));
                                p.steps[index].done = !p.steps[index].done;
                                root.b.send({ cmd: "project", project: p });
                            }
                        }
                    }
                }
                BoussoleChip {
                    text: root.b.tr("Remove the project", "Retirer le projet")
                    onClicked: root.b.send({ cmd: "project-remove", id: proj.p.id })
                }
            }
        }
    }

    BoussoleText {
        text: root.b.tr("New project", "Nouveau projet")
        font.weight: Font.Bold
    }
    BoussoleField { id: name; placeholder: root.b.tr("Name (ARGOS)", "Nom (ARGOS)") }
    BoussoleField { id: due; placeholder: root.b.tr("Due date (12/11)", "Date de remise (12/11)") }
    BoussoleField { id: subject; placeholder: root.b.tr("Subject (ACL), optional", "Matière (ACL), facultatif") }
    BoussoleField { id: steps; placeholder: root.b.tr("Steps: Analysis 4, Contact 2, Writing 6", "Étapes : Analyse 4, Contact 2, Rédaction 6") }
    BoussoleText {
        visible: root.error !== ""
        width: parent.width
        text: root.error
        color: DrawerTheme.danger
        font.pixelSize: 13
    }
    BoussolePill {
        primary: true
        text: root.b.tr("Create", "Créer")
        onClicked: {
            const d = root.b.parseDate(due.text);
            const list = steps.text.split(",").map(x => x.trim()).filter(x => x !== "").map(x => {
                const m = x.match(/^(.*?)\s+(\d+(?:[.,]\d+)?)\s*h?$/);
                return m ? { name: m[1].trim(), hours: parseFloat(m[2].replace(",", ".")) } : null;
            });
            if (name.text.trim() === "") { root.error = root.b.tr("The name is missing.", "Il manque le nom."); return; }
            if (d === "") { root.error = root.b.tr("The date is not understood (12/11).", "La date n'est pas comprise (12/11)."); return; }
            if (list.length === 0 || list.indexOf(null) !== -1) {
                root.error = root.b.tr("Each step: a name, then its hours (Analysis 4).", "Chaque étape : un nom, puis ses heures (Analyse 4).");
                return;
            }
            root.error = "";
            const project = {
                id: name.text.trim().toLowerCase().replace(/[^a-z0-9]+/g, "-"),
                name: name.text.trim(),
                domain: subject.text.trim() || null,
                due: d + "T23:59",
                steps: list
            };
            root.b.send({ cmd: "project", project: project }, () => {
                name.text = ""; due.text = ""; subject.text = ""; steps.text = "";
            });
        }
    }
}
