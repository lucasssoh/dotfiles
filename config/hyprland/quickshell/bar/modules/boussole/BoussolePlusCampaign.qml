import QtQuick
import "../../theme"
import "../../services"

// Campaigns, the work-study search first: one line per company with its
// status, touched to move it on. Time is set aside each school day until
// the end date.
Column {
    id: root

    spacing: 12
    readonly property var b: BoussoleState
    readonly property var c: root.b.campaigns.filter(x => !x.closed)[0] || null
    readonly property var statuses: [
        { id: "to-send", label: root.b.tr("to send", "à envoyer") },
        { id: "sent", label: root.b.tr("sent", "envoyée") },
        { id: "follow-up", label: root.b.tr("follow-up", "relance") },
        { id: "interview", label: root.b.tr("interview", "entretien") },
        { id: "refused", label: root.b.tr("refused", "refus") },
        { id: "offer", label: root.b.tr("offer", "offre") }
    ]
    function update(change) {
        const c = JSON.parse(JSON.stringify(root.c));
        change(c);
        root.b.send({ cmd: "campaign", campaign: c });
    }

    BoussoleText {
        text: root.c ? root.c.name : root.b.tr("Campaigns", "Campagnes")
        font.pixelSize: 18
        font.weight: Font.Bold
    }

    // ---- none yet ---------------------------------------------------------
    Column {
        visible: root.c === null
        width: parent.width
        spacing: 10
        BoussoleText {
            width: parent.width
            text: root.b.tr("A recurring effort with an end, such as looking for a work-study contract: 30 minutes each school day until then.",
                            "Un effort régulier avec une fin, comme la recherche d'alternance : 30 minutes chaque jour d'école jusque-là.")
            color: DrawerTheme.secondary
            font.pixelSize: 13
        }
        BoussoleField { id: cname; placeholder: root.b.tr("Name (Work-study)", "Nom (Alternance)") }
        BoussoleField { id: cend; placeholder: root.b.tr("Until (01/11)", "Jusqu'au (01/11)") }
        BoussolePill {
            primary: true
            text: root.b.tr("Start", "Commencer")
            onClicked: {
                const end = root.b.parseDate(cend.text);
                if (cname.text.trim() === "" || end === "") return;
                root.b.send({ cmd: "campaign", campaign: {
                    id: cname.text.trim().toLowerCase().replace(/[^a-z0-9]+/g, "-"),
                    name: cname.text.trim(), start: root.b.parseDate("today"), end: end,
                    school_day_minutes: 30, free_day_minutes: 120, weekly_target: 8
                } });
            }
        }
    }

    // ---- the campaign -----------------------------------------------------
    Column {
        visible: root.c !== null
        width: parent.width
        spacing: 10
        BoussoleText {
            width: parent.width
            text: root.c ? root.b.tr("Until ", "Jusqu'au ") + new Date(root.c.end + "T12:00").toLocaleDateString(Qt.locale(root.b.fr ? "fr_FR" : "en_US"), root.b.fr ? "d MMMM" : "MMMM d")
                           + " · " + root.c.rows.filter(r => r.status !== "to-send").length + root.b.tr(" sent", " envoyées") : ""
            color: DrawerTheme.secondary
            font.pixelSize: 13
        }
        Repeater {
            model: root.c ? root.c.rows : []
            delegate: Column {
                id: row
                required property var modelData
                required property int index
                width: root.width
                spacing: 6
                BoussoleText { text: row.modelData.name; font.weight: Font.Bold }
                Flow {
                    width: parent.width
                    spacing: 6
                    Repeater {
                        model: root.statuses
                        delegate: BoussoleChip {
                            required property var modelData
                            text: modelData.label
                            on: row.modelData.status === modelData.id
                            onClicked: {
                                const st = modelData.id;
                                root.update(c => {
                                    c.rows[row.index].status = st;
                                    if (st === "sent" && !c.rows[row.index].sent) c.rows[row.index].sent = root.b.parseDate("today");
                                });
                            }
                        }
                    }
                }
            }
        }
        BoussoleField {
            id: company
            placeholder: root.b.tr("A company, then Enter", "Une entreprise, puis Entrée")
            onAccepted: {
                if (company.text.trim() === "") return;
                const n = company.text.trim();
                root.update(c => c.rows.push({ name: n, status: "to-send" }));
                company.text = "";
            }
        }
        BoussoleChip {
            text: root.b.tr("Close the campaign", "Fermer la campagne")
            onClicked: root.update(c => c.closed = true)
        }
    }
}
