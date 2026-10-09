import QtQuick
import "../../theme"
import "../../services"

// Rhythm and periods: the typical week (each day touched to change what it
// holds), the times that shape an evening, work-study, holidays and pause.
Column {
    id: root

    spacing: 12
    readonly property var b: BoussoleState
    readonly property var r: root.b.settings.rhythm || ({})
    readonly property var kinds: ["evening", "free", "bonus", "blocks"]
    function kindLabel(k) {
        return ({ evening: root.b.tr("evening", "soir"), free: root.b.tr("free", "libre"),
                  bonus: root.b.tr("bonus", "bonus"), blocks: root.b.tr("blocks", "blocs") })[k] || k;
    }
    readonly property var dayNames: root.b.fr ? ["Lun", "Mar", "Mer", "Jeu", "Ven", "Sam", "Dim"] : ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

    component Section: BoussoleText {
        color: DrawerTheme.secondary
        font.pixelSize: 11
        font.weight: Font.Bold
        font.letterSpacing: 1
        font.capitalization: Font.AllUppercase
    }

    // A time or a number of minutes, saved on Enter.
    component Setting: Row {
        id: setting
        property string key: ""
        property string label: ""
        property bool minutes: false
        width: root.width
        spacing: 10
        BoussoleText {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - 110
            text: setting.label
            font.pixelSize: 13
        }
        BoussoleField {
            id: f
            width: 100
            text: root.r[setting.key] !== undefined ? String(root.r[setting.key]) : ""
            onAccepted: {
                const v = setting.minutes ? parseInt(f.text, 10) : f.text.trim();
                if (setting.minutes ? isNaN(v) : !/^\d{1,2}:\d{2}$/.test(v)) return;
                const patch = { rhythm: {} };
                patch.rhythm[setting.key] = v;
                root.b.setSettings(patch);
            }
        }
    }

    BoussoleText {
        text: root.b.tr("Rhythm and periods", "Rythme et périodes")
        font.pixelSize: 18
        font.weight: Font.Bold
    }

    // Focus mode: starting a session puts you in front of its file.
    readonly property var fm: root.b.settings.focus || ({})
    Section { text: root.b.tr("Focus mode", "Mode focus") }
    Row {
        spacing: 6
        BoussoleChip {
            text: root.b.tr("On", "Activé")
            on: root.fm.enabled === true
            onClicked: root.b.setSettings({ focus: { enabled: true } })
        }
        BoussoleChip {
            text: root.b.tr("Off", "Désactivé")
            on: root.fm.enabled !== true
            onClicked: root.b.setSettings({ focus: { enabled: false } })
        }
    }
    BoussoleText {
        width: parent.width
        text: root.b.tr("Starting a session takes you to the study workspaces, a dimension of their own, with its file in Liseuse and the session's panel on the right: the time, the objective, the evening's files and Next. Your own workspaces stay as they are; Pause and Close bring you back. Whatever you open there counts for the session.",
                        "Démarrer une séance t'emmène sur les bureaux d'étude, une dimension à part, avec son fichier dans Liseuse et le panneau de séance à droite : le temps, l'objectif, les fichiers de la soirée et Suivant. Tes bureaux restent comme ils sont ; Pause et Clore t'y ramènent. Tout ce que tu ouvres là-bas compte pour la séance.")
        color: DrawerTheme.secondary
        font.pixelSize: 12
    }

    Section { text: root.b.tr("Typical week · touch a day", "Semaine type · touche un jour") }
    Row {
        spacing: 4
        Repeater {
            model: 7
            delegate: Column {
                required property int index
                spacing: 4
                BoussoleText { width: 54; horizontalAlignment: Text.AlignHCenter; text: root.dayNames[index]; font.pixelSize: 12; color: DrawerTheme.secondary }
                BoussoleChip {
                    width: 54
                    readonly property string k: (root.r.week || [])[index] || ""
                    text: root.kindLabel(k)
                    on: k === "evening" || k === "blocks"
                    onClicked: {
                        const w = (root.r.week || []).slice();
                        w[index] = root.kinds[(root.kinds.indexOf(k) + 1) % root.kinds.length];
                        root.b.setSettings({ rhythm: { week: w } });
                    }
                }
            }
        }
    }
    BoussoleText {
        width: parent.width
        text: root.b.tr("Evening: one session after coming home. Free: nothing counted. Bonus: offered, never counted. Blocks: counted blocks in the day.",
                        "Soir : une séance après le retour. Libre : rien de compté. Bonus : proposé, jamais compté. Blocs : des blocs comptés dans la journée.")
        color: DrawerTheme.secondary
        font.pixelSize: 12
    }

    Section { text: root.b.tr("Times · Enter saves", "Horaires · Entrée enregistre") }
    Setting { key: "evening_target"; label: root.b.tr("Evening session from", "Séance du soir à partir de") }
    Setting { key: "evening_minutes"; minutes: true; label: root.b.tr("Evening session, minutes", "Séance du soir, minutes") }
    Setting { key: "latest_end"; label: root.b.tr("Never ending after", "Jamais de fin après") }
    Setting { key: "bedtime"; label: root.b.tr("Bedtime", "Coucher") }
    Setting { key: "commute"; minutes: true; label: root.b.tr("Commute, minutes", "Trajet, minutes") }
    Setting { key: "dinner"; minutes: true; label: root.b.tr("Dinner, minutes", "Dîner, minutes") }
    Setting { key: "morning_ready"; label: root.b.tr("Morning routine over at", "Routine du matin finie à") }
    Setting { key: "block_minutes"; minutes: true; label: root.b.tr("Blocks, minutes", "Blocs, minutes") }

    Section { text: root.b.tr("Status", "Statut") }
    Row {
        spacing: 6
        readonly property bool alt: (root.b.settings.status || {}).kind === "alternance"
        BoussoleChip {
            text: root.b.tr("Full-time studies", "Formation initiale")
            on: !parent.alt
            onClicked: root.b.setSettings({ status: { kind: "initial" } })
        }
        BoussoleChip {
            text: root.b.tr("Work-study", "Alternance")
            on: parent.alt
            onClicked: root.b.setSettings({ status: { kind: "alternance", since: root.b.parseDate("today"), work_start: "09:00", work_end: "17:30" } })
        }
    }
    BoussoleText {
        width: parent.width
        text: root.b.tr("In work-study, a week without courses in the timetable is a week at the company: evenings only.",
                        "En alternance, une semaine sans cours dans l'emploi du temps est une semaine en entreprise : le soir seulement.")
        color: DrawerTheme.secondary
        font.pixelSize: 12
    }

    Section { text: root.b.tr("Periods", "Périodes") }
    Repeater {
        model: root.b.settings.periods || []
        delegate: Row {
            required property var modelData
            width: root.width
            spacing: 10
            BoussoleText {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - 100
                text: modelData.name + " · " + modelData.start + " → " + modelData.end + " · " + modelData.rule
                font.pixelSize: 13
            }
            BoussoleChip {
                anchors.verticalCenter: parent.verticalCenter
                text: root.b.tr("Remove", "Retirer")
                onClicked: root.b.setSettings({ periods: (root.b.settings.periods || []).filter(p => p.name !== modelData.name) })
            }
        }
    }
    BoussoleField { id: pname; placeholder: root.b.tr("Name (Autumn break, week 1)", "Nom (Toussaint, semaine 1)") }
    Row {
        width: parent.width
        spacing: 8
        BoussoleField { id: pfrom; width: (parent.width - 8) / 2; placeholder: root.b.tr("From (19/10)", "Du (19/10)") }
        BoussoleField { id: pto; width: (parent.width - 8) / 2; placeholder: root.b.tr("To (25/10)", "Au (25/10)") }
    }
    property string rule: "free"
    Flow {
        width: parent.width
        spacing: 6
        Repeater {
            model: [
                { id: "normal", label: root.b.tr("As usual", "Comme d'habitude") },
                { id: "free", label: root.b.tr("Free", "Libre") },
                { id: "morning-block", label: root.b.tr("Morning block", "Bloc le matin") },
                { id: "study", label: root.b.tr("Study week", "Révisions") },
                { id: "bonus-only", label: root.b.tr("Bonus only", "Bonus seulement") },
                { id: "pause", label: root.b.tr("Pause", "Pause") }
            ]
            delegate: BoussoleChip {
                required property var modelData
                text: modelData.label
                on: root.rule === modelData.id
                onClicked: root.rule = modelData.id
            }
        }
    }
    BoussolePill {
        text: root.b.tr("Add the period", "Ajouter la période")
        onClicked: {
            const a = root.b.parseDate(pfrom.text), z = root.b.parseDate(pto.text);
            if (pname.text.trim() === "" || a === "" || z === "") return;
            root.b.setSettings({ periods: (root.b.settings.periods || []).concat([{ name: pname.text.trim(), start: a, end: z, rule: root.rule }]) },
                               () => { pname.text = ""; pfrom.text = ""; pto.text = ""; });
        }
    }

    Section { text: root.b.tr("Pause", "Pause") }
    Row {
        spacing: 8
        BoussoleField { id: until; width: 160; placeholder: root.b.tr("Until (01/11)", "Jusqu'au (01/11)") }
        BoussolePill {
            text: root.b.settings.paused_until ? root.b.tr("Resume", "Reprendre") : root.b.tr("Pause", "Mettre en pause")
            onClicked: root.b.setSettings({ paused_until: root.b.settings.paused_until ? null : (root.b.parseDate(until.text) || "9999-12-31") })
        }
    }
    BoussoleText {
        width: parent.width
        text: root.b.tr("No alerts or sessions meanwhile; your data is kept. After the exams, the pause comes on its own once the timetable holds nothing more.",
                        "Plus d'alertes ni de séances pendant ce temps ; tes données sont gardées. Après les examens, la pause vient seule dès que l'emploi du temps ne contient plus rien.")
        color: DrawerTheme.secondary
        font.pixelSize: 12
    }
}
