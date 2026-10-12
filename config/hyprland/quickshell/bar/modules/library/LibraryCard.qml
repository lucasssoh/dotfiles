import QtQuick
import "../../theme"
import "../../services"
import ".."
import "../boussole"

// The library's picker, centred on a veil (services/LibraryState.qml).
// Empty, it shows where you left off and what Boussole does next; typed
// into, the files whose title, chapter or a section holds every word,
// grouped by subject and chapter, the one selected previewed on the
// right with its sections. ↑↓ choose, Enter opens (at the section found),
// Tab the next kind, Escape steps back then closes.
Item {
    id: root

    readonly property bool open: LibraryState.open
    readonly property bool choosing: LibraryState.mode === "choose"
    readonly property var b: BoussoleState

    property string query: ""
    property string filter: "all"
    property string subject: ""
    property int current: 0

    readonly property var words: LibraryState.fold(root.query).split(" ").filter(w => w.length > 0)
    readonly property bool home: root.words.length === 0 && root.subject === "" && root.filter === "all"

    // ---- what the list shows: headers and rows, flat ------------------
    readonly property var entries: {
        const out = [];
        const add = (header, hits) => {
            if (hits.length === 0) return;
            out.push({ header: true, name: header });
            for (const h of hits) out.push({ header: false, row: h.row, section: h.section });
        };
        if (LibraryState.rows.length === 0) return out;
        if (root.home) {
            const resume = LibraryState.rows.filter(r => r.page !== "" && r.recent < 100000)
                .sort((a, c) => a.recent - c.recent).slice(0, 4).map(r => ({ row: r, section: -1 }));
            add(root.b.tr("Pick up where you left off", "Reprendre"), resume);
            const lib = LibraryState.library;
            const next = lib ? (lib.best || []).map(p => LibraryState.rows.find(r => r.id === p.item)).filter(r => r) : [];
            add(root.b.tr("Next, says Boussole", "La suite, selon Boussole"), next.map(r => ({ row: r, section: -1 })));
            return out;
        }
        const hits = LibraryState.search(root.query, root.filter, root.subject);
        let group = null, bucket = [];
        for (const h of hits.slice(0, 200)) {
            if (h.row.group !== group) {
                add(group || "", bucket);
                group = h.row.group;
                bucket = [];
            }
            bucket.push(h);
        }
        add(group || "", bucket);
        return out;
    }
    readonly property var selectable: {
        const s = [];
        root.entries.forEach((e, n) => { if (!e.header) s.push(n); });
        return s;
    }
    readonly property var selected: root.selectable.length > 0 ? root.entries[root.selectable[Math.min(root.current, root.selectable.length - 1)]] : null
    onEntriesChanged: root.current = 0

    readonly property var filters: [
        { id: "all", label: root.b.tr("All", "Tout") },
        { id: "sheet", label: root.b.tr("Sheets", "Fiches") },
        { id: "ex", label: root.b.tr("Exercises", "Exercices") },
        { id: "pdf", label: root.b.tr("Teacher's PDFs", "PDF du prof") },
        { id: "books", label: root.b.tr("Books & other", "Livres et autres") }
    ].filter(f => !root.choosing || f.id !== "books")
    readonly property var subjects: {
        const lib = LibraryState.library;
        return lib ? (lib.subjects || []).map(s => ({ id: s.id, label: s.label })) : [];
    }

    function move(d) {
        const n = root.selectable.length;
        if (n === 0) return;
        root.current = Math.max(0, Math.min(n - 1, root.current + d));
        list.positionViewAtIndex(root.selectable[root.current], ListView.Contain);
    }
    function activate(section) {
        const e = root.selected;
        if (!e) return;
        LibraryState.activate(e.row, section === undefined ? e.section : section);
    }
    function nextFilter() {
        const i = root.filters.findIndex(f => f.id === root.filter);
        root.filter = root.filters[(i + 1) % root.filters.length].id;
    }
    function back() {
        if (root.query !== "") field.text = "";
        else if (root.subject !== "") root.subject = "";
        else if (root.filter !== "all") root.filter = "all";
        else LibraryState.hide();
    }

    // The words typed, underlined where they are found.
    function lit(text) {
        let t = (text || "").replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
        if (root.words.length === 0) return t;
        const f = LibraryState.fold(text || "");
        const marks = [];
        for (const w of root.words) {
            let i = f.indexOf(w);
            if (i >= 0) marks.push([i, i + w.length]);
        }
        if (marks.length === 0) return t;
        marks.sort((a, c) => a[0] - c[0]);
        // fold() keeps lengths, so its offsets are the text's.
        const raw = text;
        let out = "", at = 0;
        const esc = s => s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
        for (const [a, z] of marks) {
            if (a < at) continue;
            out += esc(raw.slice(at, a)) + "<u>" + esc(raw.slice(a, z)) + "</u>";
            at = z;
        }
        return out + esc(raw.slice(at));
    }
    function stateText(r) {
        if (r.state === "next") return root.b.tr("next", "la suite");
        if (r.page !== "") return r.page;
        return r.detail || "";
    }
    function planText(r) {
        if (!r.course) return "";
        if (r.state === "next") return root.b.tr("Next in the plan.", "La suite du programme.");
        if (r.state === "read") return root.b.tr("Done: ", "Fait : ") + r.detail + ".";
        if (r.task) return root.b.tr("In the plan, further on.", "Au programme, un peu plus loin.");
        if (!r.planned) return root.b.tr("Not in the plan.", "Pas au programme.");
        return "";
    }

    Component.onCompleted: {
        field.text = LibraryState.initialQuery;
        field.forceActiveFocus();
    }
    Connections {
        target: LibraryState
        function onOpenChanged() {
            if (LibraryState.open) {
                field.text = LibraryState.initialQuery;
                root.subject = "";
                root.filter = "all";
                field.forceActiveFocus();
            }
        }
    }

    Rectangle {
        anchors.fill: parent
        color: "black"
        opacity: root.open ? 0.38 : 0
        Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
    }
    MouseArea {
        anchors.fill: parent
        onClicked: LibraryState.hide()
    }

    Rectangle {
        id: card
        anchors.centerIn: parent
        width: Math.min(parent.width - 48, 900)
        height: Math.min(parent.height - 96, 640)
        radius: 30
        color: DrawerTheme.panelTop
        border.width: 1
        border.color: DrawerTheme.ink(0.08)
        opacity: root.open ? 1 : 0
        scale: root.open ? 1 : 0.97
        Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
        Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
        MouseArea { anchors.fill: parent; onClicked: field.forceActiveFocus() }

        Column {
            id: top
            x: 18
            y: 18
            width: card.width - 36
            spacing: 12

            // ---- the field ------------------------------------------------
            Rectangle {
                width: parent.width
                height: 50
                radius: 25
                color: DrawerTheme.card
                Text {
                    id: glass
                    x: 18
                    anchors.verticalCenter: parent.verticalCenter
                    text: "\ue151"
                    color: DrawerTheme.secondary
                    font.family: Fonts.iconLucide
                    font.pixelSize: 18
                }
                TextInput {
                    id: field
                    anchors.left: glass.right
                    anchors.leftMargin: 12
                    anchors.right: count.left
                    anchors.rightMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                    color: DrawerTheme.primary
                    selectionColor: DrawerTheme.ink(0.3)
                    font.family: Fonts.ui
                    font.pixelSize: 17
                    clip: true
                    onTextChanged: root.query = text
                    Keys.onUpPressed: root.move(-1)
                    Keys.onDownPressed: root.move(1)
                    Keys.onReturnPressed: root.activate()
                    Keys.onEnterPressed: root.activate()
                    Keys.onTabPressed: root.nextFilter()
                    Keys.onEscapePressed: root.back()
                    Keys.onPressed: e => {
                        if (e.key === Qt.Key_PageDown) { root.move(8); e.accepted = true; }
                        else if (e.key === Qt.Key_PageUp) { root.move(-8); e.accepted = true; }
                    }
                    BoussoleText {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: field.text === ""
                        text: root.choosing
                              ? root.b.tr("A course file for the session…", "Un fichier de cours pour la séance…")
                              : root.b.tr("A title, a section's words, “oc dual”, “lpt”…", "Un titre, les mots d'une section, « oc dual », « lpt »…")
                        color: DrawerTheme.muted
                        font.pixelSize: 17
                    }
                }
                BoussoleText {
                    id: count
                    anchors.right: parent.right
                    anchors.rightMargin: 18
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.home ? (LibraryState.loadingOthers ? "…" : "")
                                    : root.selectable.length + (root.selectable.length > 1 ? root.b.tr(" files", " fichiers") : root.b.tr(" file", " fichier"))
                    color: DrawerTheme.muted
                    font.pixelSize: 12
                }
            }

            // ---- kinds, then subjects ----------------------------------------
            Flow {
                width: parent.width
                spacing: 6
                Repeater {
                    model: root.filters
                    delegate: BoussoleChip {
                        required property var modelData
                        text: modelData.label
                        on: root.filter === modelData.id
                        onClicked: { root.filter = modelData.id; field.forceActiveFocus(); }
                    }
                }
                Item { width: 10; height: 32; visible: root.subjects.length > 0 }
                Repeater {
                    model: root.subjects
                    delegate: BoussoleChip {
                        required property var modelData
                        text: modelData.label
                        on: root.subject === modelData.id
                        onClicked: { root.subject = root.subject === modelData.id ? "" : modelData.id; field.forceActiveFocus(); }
                    }
                }
            }
        }

        // ---- the list ------------------------------------------------------
        ListView {
            id: list
            x: 18
            anchors.top: top.bottom
            anchors.topMargin: 14
            anchors.bottom: hints.top
            anchors.bottomMargin: 10
            width: preview.visible ? card.width - 36 - preview.width - 14 : card.width - 36
            clip: true
            model: root.entries
            boundsBehavior: Flickable.StopAtBounds
            delegate: Item {
                id: entry
                required property var modelData
                required property int index
                readonly property bool on: root.selectable[root.current] === entry.index
                width: list.width
                height: entry.modelData.header ? 34 : 58

                BoussoleText {
                    visible: entry.modelData.header
                    x: 12
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 8
                    text: entry.modelData.header ? entry.modelData.name.toUpperCase() : ""
                    color: DrawerTheme.secondary
                    font.pixelSize: 11
                    font.weight: Font.Bold
                    font.letterSpacing: 1
                    elide: Text.ElideRight
                    width: parent.width - 24
                    wrapMode: Text.NoWrap
                }

                Rectangle {
                    visible: !entry.modelData.header
                    anchors.fill: parent
                    anchors.topMargin: 2
                    anchors.bottomMargin: 2
                    radius: 14
                    color: entry.on ? DrawerTheme.cardHover : (hit.containsMouse ? DrawerTheme.ink(0.03) : "transparent")
                    border.width: entry.on ? 1 : 0
                    border.color: DrawerTheme.muted

                    BoussoleText {
                        id: kind
                        x: 12
                        width: 70
                        anchors.verticalCenter: parent.verticalCenter
                        text: entry.modelData.header ? "" : entry.modelData.row.kindLabel
                        color: DrawerTheme.secondary
                        font.pixelSize: 11
                        font.weight: Font.DemiBold
                        wrapMode: Text.NoWrap
                        elide: Text.ElideRight
                    }
                    Column {
                        anchors.left: kind.right
                        anchors.leftMargin: 8
                        anchors.right: state.left
                        anchors.rightMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 3
                        BoussoleText {
                            width: parent.width
                            textFormat: Text.StyledText
                            text: entry.modelData.header ? "" : root.lit((entry.modelData.row.num ? entry.modelData.row.num + "  " : "") + entry.modelData.row.title)
                            font.pixelSize: 15
                            font.weight: Font.DemiBold
                            wrapMode: Text.NoWrap
                            elide: Text.ElideRight
                        }
                        BoussoleText {
                            width: parent.width
                            textFormat: Text.StyledText
                            text: {
                                if (entry.modelData.header) return "";
                                const r = entry.modelData.row;
                                if (entry.modelData.section >= 0) return root.lit(r.sections[entry.modelData.section].title);
                                return root.home ? r.group : root.lit(r.file);
                            }
                            color: DrawerTheme.secondary
                            font.pixelSize: 12
                            wrapMode: Text.NoWrap
                            elide: Text.ElideRight
                        }
                    }
                    BoussoleText {
                        id: state
                        anchors.right: parent.right
                        anchors.rightMargin: 12
                        anchors.verticalCenter: parent.verticalCenter
                        text: entry.modelData.header ? "" : root.stateText(entry.modelData.row)
                        color: !entry.modelData.header && entry.modelData.row.state === "next" ? DrawerTheme.primary : DrawerTheme.muted
                        font.pixelSize: 12
                        font.weight: !entry.modelData.header && entry.modelData.row.state === "next" ? Font.DemiBold : Font.Normal
                        wrapMode: Text.NoWrap
                    }
                    MouseArea {
                        id: hit
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            const k = root.selectable.indexOf(entry.index);
                            if (k >= 0 && k === root.current) root.activate();
                            else if (k >= 0) root.current = k;
                            field.forceActiveFocus();
                        }
                    }
                }
            }

            BoussoleText {
                anchors.centerIn: parent
                visible: root.entries.length === 0
                width: parent.width - 40
                horizontalAlignment: Text.AlignHCenter
                text: LibraryState.rows.length === 0
                      ? root.b.tr("Reading the library…", "Lecture de la bibliothèque…")
                      : root.home ? root.b.tr("Type to search, or pick a subject.", "Tape pour chercher, ou choisis une matière.")
                                  : root.b.tr("Nothing holds all these words.", "Rien ne contient tous ces mots.")
                color: DrawerTheme.secondary
            }
        }

        ThinScrollBar {
            target: list
            anchors.left: list.right
            anchors.leftMargin: 1
            anchors.top: list.top
            anchors.bottom: list.bottom
        }

        // ---- the preview ---------------------------------------------------
        Rectangle {
            id: preview
            visible: root.selected !== null
            anchors.right: parent.right
            anchors.rightMargin: 18
            anchors.top: list.top
            anchors.bottom: list.bottom
            width: 300
            radius: 22
            color: "transparent"
            border.width: 1
            border.color: DrawerTheme.ink(0.12)
            readonly property var r: root.selected ? root.selected.row : null
            readonly property int hitSection: root.selected ? root.selected.section : -1

            Column {
                id: pcol
                x: 18
                y: 18
                width: preview.width - 36
                spacing: 12

                Column {
                    width: parent.width
                    spacing: 4
                    BoussoleText {
                        width: parent.width
                        text: preview.r ? preview.r.group + (preview.r.course ? " · " + preview.r.kindLabel : "") : ""
                        color: DrawerTheme.secondary
                        font.pixelSize: 12
                    }
                    BoussoleText {
                        width: parent.width
                        text: preview.r ? preview.r.title : ""
                        font.pixelSize: 18
                        font.weight: Font.Bold
                        maximumLineCount: 3
                        elide: Text.ElideRight
                    }
                    BoussoleText {
                        width: parent.width
                        text: preview.r ? preview.r.file : ""
                        color: DrawerTheme.muted
                        font.pixelSize: 11
                        wrapMode: Text.WrapAnywhere
                        maximumLineCount: 2
                        elide: Text.ElideRight
                    }
                }
                BoussoleText {
                    width: parent.width
                    visible: text !== ""
                    text: preview.r ? root.planText(preview.r) + (preview.r.page !== "" ? (root.planText(preview.r) !== "" ? " " : "") + root.b.tr("Left at ", "Laissé à la ") + preview.r.page + "." : "") : ""
                    color: DrawerTheme.cream2
                    font.pixelSize: 13
                    lineHeight: 1.2
                }
            }

            ListView {
                id: secs
                x: 12
                anchors.top: pcol.bottom
                anchors.topMargin: 10
                anchors.bottom: actions.top
                anchors.bottomMargin: 12
                width: preview.width - 24
                clip: true
                model: preview.r ? preview.r.sections : []
                boundsBehavior: Flickable.StopAtBounds
                delegate: Rectangle {
                    id: sec
                    required property var modelData
                    required property int index
                    readonly property bool lit: sec.index === preview.hitSection
                    width: secs.width
                    height: 28
                    radius: 8
                    color: sec.lit ? DrawerTheme.cardRaised : (sh.containsMouse ? DrawerTheme.ink(0.04) : "transparent")
                    BoussoleText {
                        x: 8 + (sec.modelData.sub ? 12 : 0)
                        width: parent.width - x - 8
                        anchors.verticalCenter: parent.verticalCenter
                        text: sec.modelData.title
                        color: sec.lit ? DrawerTheme.primary : DrawerTheme.secondary
                        font.pixelSize: 12
                        wrapMode: Text.NoWrap
                        elide: Text.ElideRight
                    }
                    MouseArea {
                        id: sh
                        anchors.fill: parent
                        hoverEnabled: true
                        enabled: !root.choosing
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.activate(sec.index)
                    }
                }
            }

            ThinScrollBar {
                target: secs
                anchors.right: parent.right
                anchors.rightMargin: 1
                anchors.top: secs.top
                anchors.bottom: secs.bottom
            }

            Column {
                id: actions
                x: 18
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 18
                width: preview.width - 36
                spacing: 8
                BoussolePill {
                    width: parent.width
                    primary: true
                    text: {
                        const r = preview.r;
                        if (!r) return "";
                        if (root.choosing) return root.b.tr("Choose", "Choisir");
                        if (preview.hitSection >= 0) return root.b.tr("Open at “", "Ouvrir à « ") + r.sections[preview.hitSection].title.replace(/^\d+\s+/, "") + root.b.tr("”", " »");
                        if (r.page !== "") return root.b.tr("Resume, ", "Reprendre, ") + r.page;
                        return root.b.tr("Open", "Ouvrir");
                    }
                    onClicked: root.activate()
                }
                BoussolePill {
                    width: parent.width
                    visible: !root.choosing && preview.r !== null && (preview.r.page !== "" || preview.hitSection >= 0)
                    text: root.b.tr("Open at the start", "Ouvrir au début")
                    onClicked: LibraryState.openAtStart(preview.r)
                }
            }
        }

        Row {
            id: hints
            x: 26
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 14
            spacing: 18
            Repeater {
                model: [
                    root.b.tr("Enter  open", "Entrée  ouvrir"),
                    root.b.tr("↑ ↓  choose", "↑ ↓  choisir"),
                    root.b.tr("Tab  next kind", "Tab  type suivant"),
                    root.b.tr("Esc  back", "Échap  retour")
                ]
                delegate: BoussoleText {
                    required property var modelData
                    text: modelData
                    color: DrawerTheme.muted
                    font.pixelSize: 12
                }
            }
        }
    }
}
