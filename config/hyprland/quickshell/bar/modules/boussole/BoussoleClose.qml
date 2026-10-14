import QtQuick
import "../../theme"
import "../../services"

// "Close": where you stopped, pre-filled by what Liseuse saw, and how each
// exercise went. Anything else is done or not. Only this ends a session.
Column {
    id: root

    spacing: 22
    readonly property var b: BoussoleState
    readonly property var c: b.closing

    // What the user says, per part: { read_upto, exercises, done }.
    property var answers: []
    property var media: null
    onCChanged: {
        const out = [];
        for (const p of (root.c ? root.c.parts : [])) {
            const ex = {};
            for (const k in (p.already || {})) ex[k] = p.already[k];
            out.push({ read_upto: p.read_upto || 0, exercises: ex, done: p.kind === "other" ? p.done : false });
        }
        root.answers = out;
        root.media = null;
    }
    function setAnswer(i, key, value) {
        const a = root.answers.slice();
        a[i] = Object.assign({}, a[i]);
        a[i][key] = value;
        root.answers = a;
    }
    readonly property var outcomes: [
        { id: "solo", en: "Solved", fr: "Réussi" },
        { id: "with-solution", en: "With help", fr: "Avec aide" },
        { id: "failed", en: "Stuck", fr: "Bloqué" }
    ]

    function submit() {
        const parts = [];
        for (let i = 0; i < root.c.parts.length; i++) {
            const p = root.c.parts[i];
            const a = root.answers[i];
            if (p.kind === "study") {
                const ex = {};
                for (const k in a.exercises) if (a.exercises[k]) ex[k] = a.exercises[k];
                const all = p.exercises === 0 || Object.keys(ex).length >= p.exercises;
                const allRead = p.sections.length === 0 || a.read_upto >= p.sections[p.sections.length - 1].num;
                parts.push({
                    task: p.task, minutes: 0, planned: p.planned,
                    done: all && allRead,
                    read_upto: a.read_upto, exercises: ex,
                    assessment: null, note: null
                });
            } else {
                parts.push({ task: p.task, minutes: 0, planned: p.planned, done: a.done, note: null });
            }
        }
        root.b.submitClose(parts, root.media);
    }

    component Label: BoussoleText {
        color: DrawerTheme.secondary
        font.pixelSize: 13
        font.weight: Font.Medium
    }

    // ---- header -----------------------------------------------------------
    Item {
        width: parent.width
        height: titleText.implicitHeight
        BoussoleText {
            id: titleText
            text: root.b.tr("Close", "Clore")
            font.pixelSize: 24
            font.weight: Font.DemiBold
        }
        BoussoleText {
            anchors.right: parent.right
            anchors.baseline: titleText.baseline
            text: root.c ? root.c.title + " · " + root.c.effective_text : ""
            color: DrawerTheme.secondary
            font.pixelSize: 14
        }
    }

    // ---- per task -----------------------------------------------------------
    Repeater {
        model: root.c ? root.c.parts : []
        delegate: Column {
            id: partCol
            required property var modelData
            required property int index
            readonly property var p: modelData
            readonly property var a: root.answers[index] || ({ exercises: {} })
            width: root.width
            spacing: 10

            // Anything but a sheet: done or not.
            Label { visible: partCol.p.kind === "other"; text: partCol.p.label }
            Row {
                visible: partCol.p.kind === "other"
                spacing: 8
                BoussoleChip { text: root.b.tr("Done", "Fait"); on: partCol.a.done === true; onClicked: root.setAnswer(partCol.index, "done", true) }
                BoussoleChip { text: root.b.tr("Not done", "Pas fait"); on: partCol.a.done === false; onClicked: root.setAnswer(partCol.index, "done", false) }
            }

            // A sheet: the section reached (outlined: what Liseuse saw).
            Label {
                visible: partCol.p.kind === "study"
                text: root.b.tr("Stopped at · ", "Arrêté à · ") + partCol.p.label
                width: parent.width
                elide: Text.ElideRight
            }
            Flow {
                visible: partCol.p.kind === "study" && partCol.p.sections.length > 0
                width: parent.width
                spacing: 6
                Repeater {
                    model: partCol.p.kind === "study" ? partCol.p.sections : []
                    delegate: BoussoleChip {
                        required property var modelData
                        text: "§" + modelData.num
                        on: modelData.num <= partCol.a.read_upto
                        hinted: partCol.p.seen_upto !== null && modelData.num <= partCol.p.seen_upto
                        // Touching the § already reached steps back one.
                        onClicked: root.setAnswer(partCol.index, "read_upto",
                                                  partCol.a.read_upto === modelData.num ? modelData.num - 1 : modelData.num)
                    }
                }
            }

            Item { visible: partCol.p.kind === "study" && partCol.p.exercises > 0; width: 1; height: 4 }
            Label {
                visible: partCol.p.kind === "study" && partCol.p.exercises > 0
                text: root.b.tr("Exercises", "Exercices")
            }
            Repeater {
                model: partCol.p.kind === "study" ? partCol.p.exercises : 0
                delegate: Column {
                    id: exRow
                    required property int index
                    readonly property string st: partCol.a.exercises[index + 1] || ""
                    width: partCol.width
                    spacing: 6
                    BoussoleText {
                        text: root.b.tr("Exercise ", "Exercice ") + (exRow.index + 1)
                        font.pixelSize: 14
                    }
                    Row {
                        width: parent.width
                        spacing: 6
                        Repeater {
                            model: root.outcomes
                            delegate: BoussoleChip {
                                required property var modelData
                                width: (exRow.width - 12) / 3
                                text: root.b.tr(modelData.en, modelData.fr)
                                on: exRow.st === modelData.id
                                // Touched again: not rated.
                                onClicked: {
                                    const ex = Object.assign({}, partCol.a.exercises);
                                    ex[exRow.index + 1] = exRow.st === modelData.id ? "" : modelData.id;
                                    root.setAnswer(partCol.index, "exercises", ex);
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // ---- a video played: for the course? -----------------------------------
    Column {
        visible: root.c !== null && root.c.media_minutes > 0
        width: parent.width
        spacing: 8
        Label { text: root.c ? root.b.tr("A video, ", "Une vidéo, ") + root.c.media_minutes + root.b.tr(" min: for the course?", " min : pour le cours ?") : "" }
        Row {
            spacing: 8
            BoussoleChip { text: root.b.tr("Yes", "Oui"); on: root.media === true; onClicked: root.media = true }
            BoussoleChip { text: root.b.tr("No", "Non"); on: root.media === false; onClicked: root.media = false }
        }
    }

    Row {
        width: parent.width
        spacing: 8
        BoussolePill {
            width: (parent.width - 8) / 2
            text: root.b.tr("Back", "Retour")
            onClicked: {
                root.b.closing = null;
                root.b.thenStart = "";
                root.b.page = "today";
            }
        }
        BoussolePill {
            width: (parent.width - 8) / 2
            primary: true
            text: root.b.thenStart !== "" ? root.b.tr("Close, next file", "Clore, fichier suivant") : root.b.tr("Close session", "Clore la séance")
            onClicked: root.submit()
        }
    }
}
