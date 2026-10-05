import QtQuick
import "../../theme"
import "../../services"

// "Close": pre-filled by what Liseuse saw, confirmed by the user. For each
// sheet, the section really understood (dashed: seen, not confirmed) and
// each exercise, touched to cycle through not done / solved alone / with
// the solution / failed; how it went; a note. Anything else is done or
// not. Only this ends a session.
Column {
    id: root

    spacing: 14
    readonly property var b: BoussoleState
    readonly property var c: b.closing

    // What the user says, per part: { read_upto, exercises, assessment, done }.
    property var answers: []
    property var media: null
    onCChanged: {
        const out = [];
        for (const p of (root.c ? root.c.parts : [])) {
            const ex = {};
            for (const k in (p.already || {})) ex[k] = p.already[k];
            out.push({ read_upto: p.read_upto || 0, exercises: ex, assessment: "", done: p.kind === "other" ? p.done : false });
        }
        root.answers = out;
        root.media = null;
        note.text = "";
    }
    function setAnswer(i, key, value) {
        const a = root.answers.slice();
        a[i] = Object.assign({}, a[i]);
        a[i][key] = value;
        root.answers = a;
    }
    readonly property var cycle: ["", "solo", "with-solution", "failed"]
    function nextStatus(s) {
        return root.cycle[(root.cycle.indexOf(s || "") + 1) % root.cycle.length];
    }
    function mark(s) {
        return s === "solo" ? " ✓" : s === "with-solution" ? " ◐" : s === "failed" ? " ✗" : "";
    }

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
                    assessment: a.assessment || null,
                    note: null
                });
            } else {
                parts.push({ task: p.task, minutes: 0, planned: p.planned, done: a.done, note: null });
            }
        }
        // The note belongs to the session: it goes with its first task.
        if (parts.length > 0 && note.text !== "") parts[0].note = note.text;
        root.b.submitClose(parts, root.media);
    }

    component Section: BoussoleText {
        color: DrawerTheme.secondary
        font.pixelSize: 11
        font.weight: Font.Bold
        font.letterSpacing: 1
        font.capitalization: Font.AllUppercase
    }

    // ---- header -----------------------------------------------------------
    Column {
        width: parent.width
        spacing: 4
        BoussoleText {
            text: root.b.tr("Close the session", "Clore la séance")
            font.pixelSize: 20
            font.weight: Font.Bold
        }
        BoussoleText {
            width: parent.width
            text: root.c ? root.c.title + " · " + root.c.start + " → " + root.c.end : ""
            color: DrawerTheme.secondary
        }
    }

    // ---- what was seen, and the time --------------------------------------
    Rectangle {
        width: parent.width
        height: seenCol.implicitHeight + 28
        radius: 18
        color: DrawerTheme.card
        Column {
            id: seenCol
            x: 16
            y: 14
            width: parent.width - 32
            spacing: 6
            Section { text: root.b.tr("What Liseuse saw", "Ce que Liseuse a vu") }
            Repeater {
                model: root.c && root.c.seen.length ? root.c.seen : [root.b.tr("Nothing in Liseuse: work on paper.", "Rien dans Liseuse : travail sur papier.")]
                delegate: BoussoleText {
                    required property var modelData
                    width: seenCol.width
                    text: modelData
                }
            }
            Item { width: 1; height: 4 }
            Section { text: root.b.tr("Effective time", "Temps effectif") }
            BoussoleText {
                width: parent.width
                text: root.c ? root.c.effective_text + (root.c.game_minutes > 0 ? root.b.tr(", a game's ", ", ") + root.c.game_minutes + root.b.tr(" min taken out", " min de jeu retirées") : "") : ""
            }
            BoussoleText {
                visible: root.c !== null && root.c.media_minutes > 0
                width: parent.width
                text: root.c ? root.b.tr("A video played ", "Une vidéo a joué ") + root.c.media_minutes + root.b.tr(" min: for the course?", " min : pour le cours ?") : ""
            }
            Row {
                visible: root.c !== null && root.c.media_minutes > 0
                spacing: 8
                BoussoleChip { text: root.b.tr("Yes", "Oui"); on: root.media === true; onClicked: root.media = true }
                BoussoleChip { text: root.b.tr("No", "Non"); on: root.media === false; onClicked: root.media = false }
            }
        }
    }

    // ---- per task -------------------------------------------------------------
    Repeater {
        model: root.c ? root.c.parts : []
        delegate: Rectangle {
            id: partCard
            required property var modelData
            required property int index
            readonly property var p: modelData
            readonly property var a: root.answers[index] || ({ exercises: {} })
            width: root.width
            height: partCol.implicitHeight + 28
            radius: 18
            color: "transparent"
            border.width: 1
            border.color: DrawerTheme.faint

            Column {
                id: partCol
                x: 16
                y: 14
                width: parent.width - 32
                spacing: 10

                BoussoleText {
                    width: parent.width
                    text: partCard.p.label
                    font.weight: Font.Bold
                }

                // Anything but a sheet: done or not.
                Row {
                    visible: partCard.p.kind === "other"
                    spacing: 8
                    BoussoleChip { text: root.b.tr("Done", "Fait"); on: partCard.a.done === true; onClicked: root.setAnswer(partCard.index, "done", true) }
                    BoussoleChip { text: root.b.tr("Not done", "Pas fait"); on: partCard.a.done === false; onClicked: root.setAnswer(partCard.index, "done", false) }
                }

                Section {
                    visible: partCard.p.kind === "study" && partCard.p.sections.length > 0
                    text: root.b.tr("Understood up to", "Compris jusqu'au")
                }
                Flow {
                    visible: partCard.p.kind === "study"
                    width: parent.width
                    spacing: 6
                    Repeater {
                        model: partCard.p.kind === "study" ? partCard.p.sections : []
                        delegate: BoussoleChip {
                            required property var modelData
                            text: "§" + modelData.num
                            on: modelData.num <= partCard.a.read_upto
                            hinted: partCard.p.seen_upto !== null && modelData.num <= partCard.p.seen_upto
                            // Touching the § already reached steps back one.
                            onClicked: root.setAnswer(partCard.index, "read_upto",
                                                      partCard.a.read_upto === modelData.num ? modelData.num - 1 : modelData.num)
                        }
                    }
                }

                Section {
                    visible: partCard.p.kind === "study" && partCard.p.exercises > 0
                    text: root.b.tr("Exercises · touch to change", "Exercices · touche pour changer")
                }
                Flow {
                    visible: partCard.p.kind === "study" && partCard.p.exercises > 0
                    width: parent.width
                    spacing: 6
                    Repeater {
                        model: partCard.p.kind === "study" ? partCard.p.exercises : 0
                        delegate: BoussoleChip {
                            required property int index
                            readonly property string st: partCard.a.exercises[index + 1] || ""
                            text: "Ex " + (index + 1) + root.mark(st)
                            on: st !== ""
                            onClicked: {
                                const ex = Object.assign({}, partCard.a.exercises);
                                ex[index + 1] = root.nextStatus(st);
                                root.setAnswer(partCard.index, "exercises", ex);
                            }
                        }
                    }
                }
                BoussoleText {
                    visible: partCard.p.kind === "study" && partCard.p.exercises > 0
                    width: parent.width
                    text: root.b.tr("✓ alone · ◐ with the solution · ✗ failed (comes back in 3 days, without the solution)",
                                    "✓ seul · ◐ avec le corrigé · ✗ raté (revient dans 3 jours, sans corrigé)")
                    color: DrawerTheme.secondary
                    font.pixelSize: 12
                }

                Row {
                    visible: partCard.p.kind === "study"
                    spacing: 6
                    BoussoleChip { text: root.b.tr("Understood", "Compris"); on: partCard.a.assessment === "understood"; onClicked: root.setAnswer(partCard.index, "assessment", "understood") }
                    BoussoleChip { text: root.b.tr("To review", "À revoir"); on: partCard.a.assessment === "review"; onClicked: root.setAnswer(partCard.index, "assessment", "review") }
                    BoussoleChip { text: root.b.tr("Stuck", "Bloqué"); on: partCard.a.assessment === "blocked"; onClicked: root.setAnswer(partCard.index, "assessment", "blocked") }
                }
            }
        }
    }

    // ---- a note -----------------------------------------------------------
    Rectangle {
        width: parent.width
        height: 44
        radius: 14
        color: DrawerTheme.card
        TextInput {
            id: note
            anchors.fill: parent
            anchors.leftMargin: 14
            anchors.rightMargin: 14
            verticalAlignment: TextInput.AlignVCenter
            color: DrawerTheme.primary
            font.family: Fonts.ui
            font.pixelSize: 14
            clip: true
            selectByMouse: true
        }
        BoussoleText {
            anchors.verticalCenter: parent.verticalCenter
            x: 14
            visible: note.text === "" && !note.activeFocus
            text: root.b.tr("A line for yourself (optional)", "Une ligne pour toi (facultatif)")
            color: DrawerTheme.muted
        }
        MouseArea {
            anchors.fill: parent
            visible: !note.activeFocus
            cursorShape: Qt.IBeamCursor
            onClicked: note.forceActiveFocus()
        }
    }

    Flow {
        width: parent.width
        spacing: 8
        BoussolePill {
            primary: true
            text: root.b.tr("Close and replan", "Clore et replanifier")
            onClicked: root.submit()
        }
        BoussolePill {
            text: root.b.tr("Cancel", "Annuler")
            onClicked: {
                root.b.closing = null;
                root.b.page = "today";
            }
        }
    }
}
