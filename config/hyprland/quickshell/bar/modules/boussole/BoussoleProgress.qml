import QtQuick
import "../../theme"
import "../../services"

// Progress: the programme. One card per subject, exams first: its exam,
// the sessions to spare before it, the hours planned, and what it has
// done. Then two pages: the weeks ahead, and "what if", the margins under
// the levers that would change them, nothing kept until applied.
// Numbers and a sentence, no charts ("juste un peu de chiffres pour que ça
// reste épuré").
Column {
    id: root

    spacing: 12
    readonly property var b: BoussoleState
    readonly property bool fr: root.b.fr

    function h(n) {
        return String(n).replace(".", root.fr ? "," : ".") + " h";
    }
    function name(d) {
        return d === "RESEAUX" ? root.b.tr("Networks", "Réseaux") : d;
    }
    function marginText(m) {
        return (m > 0 ? "+" : "") + m + root.b.tr(m === 1 || m === -1 ? " session" : " sessions", m === 1 || m === -1 ? " séance" : " séances");
    }

    component Section: BoussoleText {
        color: DrawerTheme.secondary
        font.pixelSize: 11
        font.weight: Font.Bold
        font.letterSpacing: 1
        font.capitalization: Font.AllUppercase
    }

    // A margin, as a pill: comfortable, just, short; or no date at all.
    component Margin: Rectangle {
        id: pill
        property var margin: null
        readonly property bool none: pill.margin === null || pill.margin === undefined
        readonly property bool short: !pill.none && pill.margin < 0
        readonly property bool tight: !pill.none && pill.margin >= 0 && pill.margin < 5
        height: 24
        width: label.implicitWidth + 20
        radius: 12
        color: pill.short ? "#ff9f5a" : pill.tight ? "#3a2e14" : "transparent"
        border.width: pill.short || pill.tight ? 0 : 1
        border.color: DrawerTheme.faint
        BoussoleText {
            id: label
            anchors.centerIn: parent
            text: pill.none ? root.b.tr("no date", "sans date") : root.marginText(pill.margin)
            color: pill.short ? "#1a0d02" : pill.tight ? "#f3c969" : (pill.none ? DrawerTheme.secondary : DrawerTheme.primary)
            font.pixelSize: 12
            font.weight: Font.Bold
            font.features: { "tnum": 1 }
        }
    }

    // ---- the subjects --------------------------------------------------
    Column {
        visible: root.b.progressPage === ""
        width: parent.width
        spacing: 12

        BoussoleText {
            visible: root.b.progress.length === 0
            width: parent.width
            text: root.b.tr("Nothing planned yet: choose files in Files.", "Rien de planifié pour l'instant : choisis des fichiers dans Fichiers.")
            color: DrawerTheme.secondary
        }

        BoussoleText {
            visible: root.b.progress.length > 0
            width: parent.width
            text: root.b.tr("What fits before each exam, at the rhythm set. A session is one slot of the plan.",
                            "Ce qui tient avant chaque examen, au rythme réglé. Une séance est un créneau du planning.")
            color: DrawerTheme.secondary
            font.pixelSize: 13
        }

        Repeater {
            model: root.b.progress
            delegate: Rectangle {
                id: card
                required property var modelData
                readonly property var d: modelData
                readonly property bool short: card.d.exam !== null && card.d.exam.margin < 0
                readonly property bool undated: card.d.exam === null && card.d.level !== "td-only"
                width: root.width
                height: col.implicitHeight + 28
                radius: 18
                color: DrawerTheme.card
                border.width: card.short ? 1 : 0
                border.color: "#ff9f5a"

                Column {
                    id: col
                    x: 16
                    y: 14
                    width: parent.width - 32
                    spacing: 6

                    Row {
                        width: parent.width
                        spacing: 10
                        Column {
                            width: parent.width - pill.width - 10
                            spacing: 1
                            BoussoleText {
                                width: parent.width
                                text: root.name(card.d.domain)
                                font.pixelSize: 15
                                font.weight: Font.Bold
                            }
                            BoussoleText {
                                width: parent.width
                                text: card.d.exam
                                      ? root.b.tr("Exam · ", "Examen · ") + card.d.exam.date + (card.d.exam.time ? " · " + card.d.exam.time : "")
                                      : root.b.tr("No exam date", "Pas de date d'examen") + (card.d.level === "behind" ? root.b.tr(" · behind", " · en retard") : "")
                                color: DrawerTheme.secondary
                                font.pixelSize: 12
                            }
                        }
                        Margin {
                            id: pill
                            anchors.verticalCenter: parent.verticalCenter
                            margin: card.d.exam ? card.d.exam.margin : null
                        }
                    }

                    BoussoleText {
                        width: parent.width
                        text: {
                            const d = card.d;
                            let t = root.h(d.hours) + root.b.tr(" planned", " placées");
                            if (d.exam && d.exam.margin < 0)
                                t += root.b.tr(", " + (-d.exam.margin) + " sessions short.", ", il manque " + (-d.exam.margin) + " séances.");
                            else if (d.exam && d.exam.margin < 5)
                                t += root.b.tr(": it all fits, with nothing to spare.", " : tout passe, sans marge pour un imprévu.");
                            else if (!d.exam && d.level === "behind")
                                t += root.b.tr(". Behind and without a date, it goes before subjects that have one.", ". En retard et sans date, elle passe devant celles qui en ont une.");
                            else if (!d.exam && d.level !== "td-only")
                                t += root.b.tr(". Without a date, it only gets what is left.", ". Sans date, elle ne reçoit que les restes.");
                            else
                                t += ".";
                            return t;
                        }
                        color: card.short ? DrawerTheme.primary : DrawerTheme.secondary
                        font.pixelSize: 13
                    }
                    BoussoleText {
                        visible: card.d.total > 0
                        width: parent.width
                        text: card.d.studied + " / " + card.d.total + root.b.tr(" files studied", " fichiers étudiés")
                              + (card.d.exercises > 0 ? root.b.tr(" · exercises solved alone ", " · exercices réussis seul ") + card.d.exercises_solo + " / " + card.d.exercises : "")
                              + (card.d.reviews_due > 0 ? " · " + card.d.reviews_due + root.b.tr(" reviews waiting", " révisions en attente") : "")
                        color: DrawerTheme.muted
                        font.pixelSize: 12
                        font.features: { "tnum": 1 }
                    }
                    Item { width: 1; height: 2; visible: card.short || card.undated }
                    BoussolePill {
                        visible: card.short
                        primary: true
                        text: root.b.tr("See the levers", "Voir les leviers")
                        onClicked: root.b.openProgramme("whatif")
                    }
                    BoussolePill {
                        visible: card.undated
                        text: root.b.tr("Add the exam date", "Ajouter la date d'examen")
                        onClicked: root.b.openPlus("deadlines")
                    }
                }
            }
        }

        Row {
            visible: root.b.progress.length > 0
            spacing: 8
            BoussolePill {
                text: root.b.tr("Week by week", "Semaine par semaine")
                onClicked: root.b.openProgramme("weeks")
            }
            BoussolePill {
                text: root.b.tr("What if…", "Et si…")
                onClicked: root.b.openProgramme("whatif")
            }
        }
    }

    // ---- week by week ----------------------------------------------------
    Column {
        visible: root.b.progressPage === "weeks"
        width: parent.width
        spacing: 4

        BoussoleText {
            text: root.b.tr("‹ The programme", "‹ Le programme")
            color: DrawerTheme.secondary
            font.pixelSize: 13
            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.b.progressPage = "" }
        }
        BoussoleText {
            text: root.b.tr("Week by week", "Semaine par semaine")
            font.pixelSize: 18
            font.weight: Font.Bold
        }
        BoussoleText {
            width: parent.width
            text: root.b.tr("The hours planned, and what takes them.", "Les heures planifiées, et ce qui les prend.")
            color: DrawerTheme.secondary
            font.pixelSize: 13
        }
        Item { width: 1; height: 6 }
        Repeater {
            model: root.b.weeks
            delegate: Item {
                required property var modelData
                width: root.width
                height: 34
                Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: DrawerTheme.accentSoft }
                BoussoleText {
                    x: 0
                    anchors.verticalCenter: parent.verticalCenter
                    width: 110
                    text: modelData.week
                    color: DrawerTheme.secondary
                    font.pixelSize: 13
                }
                BoussoleText {
                    x: 110
                    anchors.verticalCenter: parent.verticalCenter
                    width: 52
                    horizontalAlignment: Text.AlignRight
                    text: root.h(modelData.hours)
                    font.pixelSize: 13
                    font.weight: Font.Bold
                    font.features: { "tnum": 1 }
                }
                Row {
                    x: 176
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 6
                    BoussoleText {
                        text: modelData.top.length
                              ? modelData.top.map(t => root.name(t.domain) + " " + root.h(t.hours)).join(" · ")
                              : root.b.tr("almost nothing", "presque rien")
                        color: modelData.top.length ? DrawerTheme.primary : DrawerTheme.muted
                        font.pixelSize: 13
                    }
                    Repeater {
                        model: modelData.exams
                        delegate: Rectangle {
                            required property var modelData
                            height: 18
                            width: ex.implicitWidth + 12
                            radius: 9
                            color: DrawerTheme.on
                            anchors.verticalCenter: parent.verticalCenter
                            BoussoleText {
                                id: ex
                                anchors.centerIn: parent
                                text: modelData.replace("RESEAUX", root.name("RESEAUX"))
                                color: DrawerTheme.onInk
                                font.pixelSize: 11
                                font.weight: Font.Bold
                            }
                        }
                    }
                }
            }
        }
    }

    // ---- what if ---------------------------------------------------------
    // The levers worth offering, from the settings as they are: each a
    // merge patch, tried together on the service, applied only on demand.
    readonly property var settings: root.b.settings || ({})
    readonly property var levers: {
        const s = root.settings, r = s.rhythm || {}, out = [];
        const week = r.week || [];
        if (week.length === 7 && week[5] !== "blocks")
            out.push({ id: "sat", title: root.b.tr("Saturday: two 90-minute blocks", "Samedi : deux blocs de 90 min"),
                       cost: root.b.tr("3 h more a week; Saturday stops being a bonus.", "3 h de plus par semaine, le samedi n'est plus un bonus."),
                       apply: (p) => { const w = week.slice(); w[5] = "blocks"; p.rhythm = Object.assign(p.rhythm || {}, { week: w }); } });
        if ((r.evening_minutes || 0) < 90)
            out.push({ id: "eve", title: root.b.tr("Evenings at 90 min instead of ", "Soirs à 90 min au lieu de ") + r.evening_minutes,
                       cost: root.b.tr("Monday to Thursday, a little later.", "Du lundi au jeudi, fin un peu plus tard."),
                       apply: (p) => { p.rhythm = Object.assign(p.rhythm || {}, { evening_minutes: 90 }); } });
        const today = new Date().toISOString().slice(0, 10);
        const periods = s.periods || [];
        periods.forEach((per, i) => {
            if (per.end >= today && (per.rule === "morning-block" || per.rule === "normal"))
                out.push({ id: "per" + i, title: per.name + root.b.tr(" as a study week", " en révisions"),
                           cost: root.b.tr("Two blocks a day on top of the evening.", "Deux blocs par jour en plus du soir."),
                           apply: (p) => { const ps = (p.periods || periods).map(x => Object.assign({}, x)); ps[i].rule = "study"; p.periods = ps; } });
        });
        const dated = (root.b.progress || []).filter(d => d.exam).map(d => d.domain);
        (s.domains || []).forEach((d, i) => {
            if (d.level === "behind" && !d.archived && dated.indexOf(d.id) < 0)
                out.push({ id: "lvl" + i, group: "spread", title: root.name(d.id) + root.b.tr(" rated “unsure” instead of “behind”", " notée « moyen » au lieu de « en retard »"),
                           cost: root.b.tr("It no longer goes before the subjects that have an exam.", "Elle ne passe plus devant les matières qui ont un examen."),
                           apply: (p) => { const ds = (p.domains || s.domains).map(x => Object.assign({}, x)); ds[i].level = "shaky"; p.domains = ds; } });
        });
        return out;
    }
    property var picked: ({})
    function patch() {
        const p = {};
        root.levers.forEach(l => { if (root.picked[l.id]) l.apply(p); });
        return p;
    }
    function toggle(id) {
        const next = Object.assign({}, root.picked);
        next[id] = !next[id];
        root.picked = next;
        const p = root.patch();
        if (Object.keys(p).length) root.b.tryPatch(p);
        else root.b.whatIf = [];
    }
    readonly property var shownMargins: {
        if (root.b.whatIf.length) return root.b.whatIf;
        return (root.b.progress || []).filter(d => d.exam).map(d => ({ domain: d.domain, date: d.exam.date, sessions: d.exam.margin }));
    }
    readonly property int worst: root.shownMargins.reduce((m, x) => Math.min(m, x.sessions), 0)
    Connections {
        target: root.b
        function onProgressPageChanged() {
            if (root.b.progressPage !== "whatif") {
                root.picked = ({});
                root.b.whatIf = [];
            }
        }
    }

    Column {
        visible: root.b.progressPage === "whatif"
        width: parent.width
        spacing: 8

        BoussoleText {
            text: root.b.tr("‹ The programme", "‹ Le programme")
            color: DrawerTheme.secondary
            font.pixelSize: 13
            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.b.progressPage = "" }
        }
        BoussoleText {
            text: root.b.tr("What if…", "Et si…")
            font.pixelSize: 18
            font.weight: Font.Bold
        }
        BoussoleText {
            width: parent.width
            text: root.b.tr("Each lever, and what it changes to the margins. Nothing is applied until you say so.",
                            "Chaque levier, et ce qu'il change aux marges. Rien n'est appliqué tant que tu ne valides pas.")
            color: DrawerTheme.secondary
            font.pixelSize: 13
        }
        BoussoleText {
            visible: root.levers.length === 0
            width: parent.width
            text: root.b.tr("No lever left: the rhythm is already at its fullest.", "Plus de levier : le rythme est déjà au plus plein.")
            color: DrawerTheme.secondary
            font.pixelSize: 13
        }

        Repeater {
            model: root.levers
            delegate: Rectangle {
                id: lever
                required property var modelData
                readonly property bool on: root.picked[modelData.id] === true
                width: root.width
                height: leverCol.implicitHeight + 24
                radius: 16
                color: lever.on ? DrawerTheme.cardHover : DrawerTheme.card
                border.width: 1
                border.color: lever.on ? DrawerTheme.primary : DrawerTheme.accentStrong
                Behavior on color { ColorAnimation { duration: 120 } }
                Behavior on border.color { ColorAnimation { duration: 120 } }
                scale: leverHit.pressed ? 0.98 : 1
                Behavior on scale { NumberAnimation { duration: 90; easing.type: Easing.OutCubic } }
                // The switch.
                Rectangle {
                    x: 14
                    anchors.verticalCenter: parent.verticalCenter
                    width: 40
                    height: 24
                    radius: 12
                    color: lever.on ? DrawerTheme.on : DrawerTheme.cardRaised
                    Behavior on color { ColorAnimation { duration: 140 } }
                    Rectangle {
                        y: 3
                        x: lever.on ? 19 : 3
                        width: 18
                        height: 18
                        radius: 9
                        color: lever.on ? DrawerTheme.onInk : DrawerTheme.secondary
                        Behavior on x { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                    }
                }
                Column {
                    id: leverCol
                    x: 68
                    y: 12
                    width: parent.width - 82
                    spacing: 2
                    BoussoleText { width: parent.width; text: lever.modelData.title; font.pixelSize: 14; font.weight: Font.Bold }
                    BoussoleText { width: parent.width; text: lever.modelData.cost; color: DrawerTheme.secondary; font.pixelSize: 12 }
                }
                MouseArea {
                    id: leverHit
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.toggle(lever.modelData.id)
                }
            }
        }

        Item { width: 1; height: 4 }
        Section { text: root.b.tr("The margins", "Les marges") }
        Rectangle {
            width: root.width
            height: marginCol.implicitHeight + 24
            radius: 16
            color: DrawerTheme.card
            Column {
                id: marginCol
                x: 16
                y: 12
                width: parent.width - 32
                spacing: 8
                Repeater {
                    model: root.shownMargins
                    delegate: Row {
                        required property var modelData
                        width: marginCol.width
                        BoussoleText {
                            width: parent.width - num.width
                            text: root.name(modelData.domain) + "  ·  " + modelData.date
                            color: DrawerTheme.secondary
                            font.pixelSize: 13
                        }
                        BoussoleText {
                            id: num
                            text: root.marginText(modelData.sessions)
                            color: modelData.sessions < 0 ? "#ff9f5a" : modelData.sessions < 5 ? "#f3c969" : DrawerTheme.primary
                            font.pixelSize: 15
                            font.weight: Font.Bold
                            font.features: { "tnum": 1 }
                        }
                    }
                }
                BoussoleText {
                    width: parent.width
                    text: root.worst >= 0
                          ? root.b.tr("Everything fits before each exam.", "Tout tient avant chaque examen.")
                          : root.worst > -10
                            ? root.b.tr("Nearly: " + (-root.worst) + " sessions short, to make up in free time.", "Presque : il manque " + (-root.worst) + " séances, à rattraper sur les temps libres.")
                            : root.b.tr((-root.worst) + " sessions still short: combine levers, or give the exam dates still missing.", "Il manque encore " + (-root.worst) + " séances : combine des leviers, ou donne les dates d'examen qui manquent.")
                    color: DrawerTheme.secondary
                    font.pixelSize: 12
                }
            }
        }
        BoussolePill {
            visible: Object.keys(root.patch()).length > 0
            width: root.width
            primary: true
            text: root.b.tr("Apply these settings", "Appliquer ces réglages")
            onClicked: root.b.setSettings(root.patch(), () => {
                root.picked = ({});
                root.b.whatIf = [];
                root.b.show("progress");
            })
        }
    }
}
