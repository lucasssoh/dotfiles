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
    readonly property var b: BoussoleState
    readonly property int step: b.setupStep
    readonly property var titles: [
        root.b.tr("Your courses", "Tes cours"),
        root.b.tr("Your timetable", "Ton emploi du temps"),
        root.b.tr("Courses and subjects", "Relier cours et matières"),
        root.b.tr("Your rhythm", "Ton rythme"),
        root.b.tr("Ready", "Prêt")
    ]
    // Suggested names chosen, per folder: { "L&MC": ["Logique et …"] }.
    property var chosen: ({})
    property string planned: ""

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
    BoussoleText {
        text: root.step + " · " + root.titles[root.step - 1]
        font.pixelSize: 20
        font.weight: Font.Bold
    }

    // ---- 1 · the course folder ------------------------------------------------
    Column {
        visible: root.step === 1
        width: parent.width
        spacing: 10
        Row {
            spacing: 6
            BoussoleChip { text: "Français"; on: root.b.fr; onClicked: root.b.setSettings({ lang: "fr" }) }
            BoussoleChip { text: "English"; on: !root.b.fr; onClicked: root.b.setSettings({ lang: "en" }) }
        }
        BoussoleText {
            width: parent.width
            text: root.b.tr("The folder holding one folder per subject. Boussole only reads it; new files will wait for you to plan them.",
                            "Le dossier qui contient un dossier par matière. Boussole ne fait que le lire ; les nouveaux fichiers attendront que tu les planifies.")
            color: DrawerTheme.secondary
            font.pixelSize: 13
        }
        BoussoleField {
            id: folder
            text: root.b.settings.courses || ""
            placeholder: "~/courses/…"
            onAccepted: root.b.setSettings({ courses: folder.text.trim().replace(/^~/, Quickshell.env("HOME")) }, () => root.b.refreshFiles())
        }
        BoussoleText {
            width: parent.width
            visible: root.b.files !== null && root.b.files.domains.length > 0
            text: root.b.files ? root.b.tr("Found: ", "Trouvé : ") + root.b.files.domains.map(d => d.domain + " (" + d.items.length + ")").join(" · ") : ""
            font.pixelSize: 13
        }
    }

    // ---- 2 · the timetable ----------------------------------------------------
    Loader {
        active: root.step === 2
        visible: active
        width: parent.width
        sourceComponent: BoussolePlusCalendars {}
    }

    // ---- 3 · courses and subjects ---------------------------------------------
    Column {
        visible: root.step === 3
        width: parent.width
        spacing: 10
        BoussoleText {
            width: parent.width
            text: root.b.tr("Which timetable courses belong to which folder. Suggestions are ticked; untick what is wrong.",
                            "Quels cours de l'emploi du temps vont avec quel dossier. Les propositions sont cochées ; décoche ce qui est faux.")
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
                BoussoleText { text: sug.modelData; font.weight: Font.Bold }
                BoussoleText {
                    visible: sug.names.length === 0
                    text: root.b.tr("No course found for it: name it later in More › Subjects.", "Aucun cours trouvé : à nommer plus tard dans Plus › Matières.")
                    color: DrawerTheme.secondary
                    font.pixelSize: 12
                }
                Flow {
                    width: parent.width
                    spacing: 6
                    Repeater {
                        model: sug.names
                        delegate: BoussoleChip {
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
        sourceComponent: BoussolePlusRhythm {}
    }

    // ---- 5 · ready --------------------------------------------------------------
    Column {
        visible: root.step === 5
        width: parent.width
        spacing: 10
        BoussoleText {
            width: parent.width
            text: root.b.tr("Plan the structured material now (maps, sheets, exercises)? PDFs and notes stay in Files, to decide one by one.",
                            "Planifier dès maintenant le matériel structuré (cartes, fiches, exercices) ? Les PDF et les notes restent dans Fichiers, à décider un par un.")
            font.pixelSize: 13
        }
        BoussolePill {
            text: root.planned === "" ? root.b.tr("Plan the structured material", "Planifier le matériel structuré")
                                      : root.planned + root.b.tr(" files planned", " fichiers planifiés")
            onClicked: root.b.request({ cmd: "plan-structured" }, (r) => root.planned = r.text || "0")
        }
        BoussoleText {
            width: parent.width
            text: root.b.tr("Exams not in the timetable, projects and the work-study search are added in More, or with Super + Shift + D.",
                            "Les examens absents de l'emploi du temps, les projets et la recherche d'alternance s'ajoutent dans Plus, ou avec Super + Maj + D.")
            color: DrawerTheme.secondary
            font.pixelSize: 13
        }
    }

    // ---- the way on -------------------------------------------------------------
    Flow {
        width: parent.width
        spacing: 8
        BoussolePill {
            visible: root.step > 1
            text: root.b.tr("Back", "Retour")
            onClicked: root.b.setupStep = root.step - 1
        }
        BoussolePill {
            visible: root.step < 5
            primary: true
            text: root.step === 3 ? root.b.tr("Use these links", "Utiliser ces liens") : root.b.tr("Next", "Suivant")
            onClicked: {
                if (root.step === 3) {
                    // Every folder becomes a subject, with the names kept.
                    const old = root.b.settings.domains || [];
                    const list = Object.keys(root.b.suggestions).map(id => {
                        const was = old.find(d => d.id === id) || { id: id, spaced: true };
                        const names = root.chosen[id] !== undefined ? root.chosen[id] : (root.b.suggestions[id] || []);
                        return Object.assign({}, was, { calendar_names: names.length ? names : (was.calendar_names || []) });
                    });
                    root.b.setSettings({ domains: list }, () => root.next());
                } else {
                    root.next();
                }
            }
        }
        BoussolePill {
            visible: root.step === 5
            primary: true
            text: root.b.tr("Done", "C'est prêt")
            onClicked: root.b.show("today")
        }
    }
}
