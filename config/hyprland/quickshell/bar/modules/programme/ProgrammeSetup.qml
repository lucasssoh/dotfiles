import QtQuick
import Quickshell
import "../../theme"
import "../../services"

// The first run, in five steps: the course folder, the timetable and its
// groups, which course goes with which folder, the rhythm, then ready.
// Every step is pre-filled from what is already set, so running it again
// erases nothing.
Column {
    id: root

    spacing: 14
    readonly property var b: ProgrammeState
    readonly property int step: b.setupStep
    readonly property var titles: [
        root.b.tr("Your courses", "Tes cours"),
        root.b.tr("Your timetable", "Ton emploi du temps"),
        root.b.tr("Courses and modules", "Relier cours et modules"),
        root.b.tr("Your rhythm", "Ton rythme"),
        root.b.tr("Ready", "Prêt")
    ]
    // Suggested names chosen, per folder: { "L&MC": ["Logique et …"] }.
    property var chosen: ({})

    function next() {
        if (root.step === 2) root.b.loadSuggestions();
        root.b.setupStep = Math.min(5, root.step + 1);
    }

    // ---- where we are ---------------------------------------------------------
    Row {
        spacing: 6
        Repeater {
            model: 5
            delegate: Rectangle {
                required property int index
                width: index + 1 === root.step ? 22 : 8
                height: 8
                radius: 4
                color: index + 1 <= root.step ? DrawerTheme.primary : DrawerTheme.faint
            }
        }
    }
    ProgrammeText {
        text: root.step + " · " + root.titles[root.step - 1]
        font.pixelSize: 20
        font.weight: Font.DemiBold
    }

    // ---- 1 · the course folder ------------------------------------------------
    Column {
        visible: root.step === 1
        width: parent.width
        spacing: 10
        Row {
            spacing: 6
            ProgrammeChip { text: "Français"; on: root.b.fr; onClicked: root.b.setSettings({ lang: "fr" }) }
            ProgrammeChip { text: "English"; on: !root.b.fr; onClicked: root.b.setSettings({ lang: "en" }) }
        }
        ProgrammeText {
            width: parent.width
            text: root.b.tr("One folder per subject. Programme only reads it.",
                            "Un dossier par module. Programme ne fait que le lire.")
            color: DrawerTheme.secondary
            font.pixelSize: 13
        }
        ProgrammeField {
            id: folder
            text: root.b.settings.courses || ""
            placeholder: "~/courses/…"
            onAccepted: root.b.setSettings({ courses: folder.text.trim().replace(/^~/, Quickshell.env("HOME")) }, () => root.b.openSetup())
        }
        ProgrammeText {
            width: parent.width
            visible: root.b.folders.length > 0
            text: root.b.tr("Found: ", "Trouvé : ") + root.b.folders.join(" · ")
            font.pixelSize: 13
        }
    }

    // ---- 2 · the timetable ----------------------------------------------------
    Loader {
        active: root.step === 2
        visible: active
        width: parent.width
        sourceComponent: ProgrammePlusCalendars {}
    }

    // ---- 3 · courses and subjects ---------------------------------------------
    Column {
        visible: root.step === 3
        width: parent.width
        spacing: 10
        ProgrammeText {
            width: parent.width
            text: root.b.tr("Tick each subject's courses in the timetable. The likely ones are already ticked.",
                            "Coche les cours de chaque module dans l'emploi du temps. Les plus probables sont déjà cochés.")
            color: DrawerTheme.secondary
            font.pixelSize: 13
        }
        Repeater {
            model: Object.keys(root.b.suggestions)
            delegate: Column {
                id: sug
                required property var modelData
                readonly property var names: root.b.suggestions[modelData] || []
                readonly property var picked: root.chosen[modelData] !== undefined ? root.chosen[modelData] : names
                width: root.width
                spacing: 6
                ProgrammeText { text: sug.modelData; font.weight: Font.DemiBold }
                ProgrammeText {
                    visible: sug.names.length === 0
                    text: root.b.tr("No course found for this subject. Run the first launch again to name it.", "Aucun cours trouvé pour ce module. Refais le premier lancement pour le nommer.")
                    color: DrawerTheme.secondary
                    font.pixelSize: 12
                }
                Flow {
                    width: parent.width
                    spacing: 6
                    Repeater {
                        model: sug.names
                        delegate: ProgrammeChip {
                            required property var modelData
                            text: modelData
                            on: sug.picked.indexOf(modelData) !== -1
                            onClicked: {
                                const c = Object.assign({}, root.chosen);
                                const v = modelData;
                                c[sug.modelData] = on ? sug.picked.filter(x => x !== v) : sug.picked.concat([v]);
                                root.chosen = c;
                            }
                        }
                    }
                }
            }
        }
    }

    // ---- 4 · the rhythm -------------------------------------------------------
    Loader {
        active: root.step === 4
        visible: active
        width: parent.width
        sourceComponent: ProgrammePlusRhythm {}
    }

    // ---- 5 · ready --------------------------------------------------------------
    Column {
        visible: root.step === 5
        width: parent.width
        spacing: 10
        ProgrammeText {
            width: parent.width
            text: root.b.tr("A subject can open in Boussole when its session starts.",
                            "Un module peut s'ouvrir dans Boussole quand sa séance commence.")
            font.pixelSize: 13
        }
        ProgrammePill {
            text: root.b.tr("Subjects", "Modules")
            onClicked: {
                root.b.show("plus");
                root.b.plusPage = "subjects";
            }
        }
        ProgrammeText {
            width: parent.width
            text: root.b.tr("Exams missing from the timetable, projects and your work-study search go in More, or Super + Shift + D.",
                            "Les examens absents de l'emploi du temps, les projets et ta recherche d'alternance vont dans Plus, ou Super + Maj + D.")
            color: DrawerTheme.secondary
            font.pixelSize: 13
        }
    }

    // ---- the way on -------------------------------------------------------------
    Flow {
        width: parent.width
        spacing: 8
        ProgrammePill {
            visible: root.step > 1
            text: root.b.tr("Back", "Retour")
            onClicked: root.b.setupStep = root.step - 1
        }
        ProgrammePill {
            visible: root.step < 5
            primary: true
            text: root.step === 3 ? root.b.tr("Use these links", "Utiliser ces liens") : root.b.tr("Next", "Suivant")
            onClicked: {
                if (root.step === 3) {
                    // Every folder becomes a subject, with the names kept.
                    const old = root.b.settings.domains || [];
                    const list = Object.keys(root.b.suggestions).map(id => {
                        const was = old.find(d => d.id === id) || { id: id };
                        const names = root.chosen[id] !== undefined ? root.chosen[id] : (root.b.suggestions[id] || []);
                        return Object.assign({}, was, { calendar_names: names.length ? names : (was.calendar_names || []) });
                    });
                    root.b.setSettings({ domains: list }, () => root.next());
                } else {
                    root.next();
                }
            }
        }
        ProgrammePill {
            visible: root.step === 5
            primary: true
            text: root.b.tr("Done", "C'est prêt")
            onClicked: root.b.show("today")
        }
    }
}
