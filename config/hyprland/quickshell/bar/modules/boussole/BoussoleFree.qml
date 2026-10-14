import QtQuick
import "../../theme"
import "../../services"

// "I have time": any file, with the plan's next steps put forward. A
// subject (or the most useful across all), its next three tasks with
// their reason, then every file of it by chapter, or any course file
// through the library's picker. What is chosen is said against the plan
// ("next", "further on", "off the path: the next step stays …") and
// started for the time given; the plan makes room around it.
//
// `span`: the time there is (a free period at school runs to its end),
// 0 to choose it; `school`: paper and pen.
Column {
    id: root

    property int span: 0
    property bool school: false
    property string until: ""

    readonly property var b: BoussoleState
    readonly property var lib: LibraryState.library
    property string subject: ""
    // The pick: { item, task, title, where, minutes, state, subject }.
    property var picked: null
    property int minutes: 45
    property var open: ({})
    property string note: ""

    spacing: 14

    Component.onCompleted: LibraryState.refreshLibrary()
    Connections {
        target: root.b
        function onPanelOpenChanged() { if (root.b.panelOpen) LibraryState.refreshLibrary(); }
    }

    readonly property var subjectData: root.lib ? (root.lib.subjects || []).find(s => s.id === root.subject) || null : null
    // A row of the library by item id: title, chapter, state.
    function rowOf(item) {
        return item ? LibraryState.rowsById[item] || null : null;
    }
    readonly property var recs: {
        if (!root.lib) return [];
        const list = root.subjectData ? root.subjectData.next : (root.lib.best || []);
        return list.map(p => {
            const r = root.rowOf(p.item);
            return {
                item: p.item || "", task: p.task, why: p.why, minutes: p.minutes,
                title: r ? (r.num ? r.num + "  " : "") + r.title : p.title,
                where: r ? (root.subjectData ? r.chapter : r.group) : (p.domain || ""),
                state: r ? r.state : "", subject: r ? r.subjectLabel : (p.domain || "")
            };
        });
    }
    readonly property var nextUp: root.recs.length > 0 ? root.recs[0] : null
    // Nothing picked by hand: the first suggestion.
    readonly property var chosen: root.picked || root.nextUp
    onRecsChanged: if (root.picked && !root.rowOf(root.picked.item) && root.picked.item !== "") root.picked = null

    function pick(p) {
        root.picked = p;
        if (!root.school) root.minutes = p.minutes <= 30 ? 30 : p.minutes <= 45 ? 45 : p.minutes <= 60 ? 60 : 90;
    }
    function pickRow(r) {
        root.pick({ item: r.id, task: r.task, title: (r.num ? r.num + "  " : "") + r.title, where: r.group, minutes: r.minutes, state: r.state, subject: r.subjectLabel });
    }

    readonly property string verdict: {
        const c = root.chosen, n = root.nextUp;
        if (!c) return "";
        const name = t => "« " + t.replace(/^\d+\s+/, "") + " »";
        const at = root.recs.findIndex(r => r.task === c.task && r.item === c.item);
        const there = root.b.focus && root.b.focus.enabled
            ? root.b.tr(" It opens in the study workspaces.", " Elle s'ouvre dans la dimension étude.") : "";
        if (at === 0) return root.b.tr("Recommended: next in the plan.", "Recommandé : la suite du programme.") + there;
        if (at > 0) return root.b.tr("In the plan, a little further. ", "Dans la suite, un peu plus loin. ") + name(n.title)
                           + root.b.tr(" is still to do; Boussole will offer it again.", " reste à faire ; Boussole te la reproposera.");
        const rest = n ? root.b.tr(" Next stays ", " La suite reste ") + name(n.title) + "." : "";
        if (c.state === "read") return root.b.tr("Done already: a second pass, counted for ", "Déjà faite : une relecture, comptée pour ") + c.subject + "." + rest;
        return root.b.tr("Off the path: it counts for ", "Hors de la suite : ça compte pour ") + c.subject
               + root.b.tr(" and the plan makes room.", " et le programme s'ajuste.") + rest;
    }

    function start() {
        const c = root.chosen;
        if (!c) return;
        const m = root.school ? root.span : root.minutes;
        const done = r => root.note = r.ok ? "" : (r.text || "");
        if (c.item !== "")
            root.b.request({ cmd: "free", minutes: m, item: c.item, place: root.school ? "school" : "home" }, done);
        else
            root.b.startNow(c.task, m, root.school, done);
    }

    // ---- for what --------------------------------------------------------
    Flow {
        width: parent.width
        spacing: 6
        Repeater {
            model: [{ id: "", label: root.b.tr("Most useful", "Au plus utile") }]
                   .concat(root.lib ? (root.lib.subjects || []).map(s => ({ id: s.id, label: s.label })) : [])
            delegate: BoussoleChip {
                required property var modelData
                text: modelData.label
                on: root.subject === modelData.id
                onClicked: { root.subject = modelData.id; root.picked = null; }
            }
        }
    }

    // ---- next ------------------------------------------------------------
    BoussoleText {
        visible: root.recs.length > 0
        text: root.b.tr("Next", "La suite")
        color: DrawerTheme.secondary
        font.pixelSize: 11
        font.weight: Font.Bold
        font.letterSpacing: 1
        font.capitalization: Font.AllUppercase
    }
    Repeater {
        model: root.recs
        delegate: Rectangle {
            id: rec
            required property var modelData
            required property int index
            readonly property bool on: root.chosen !== null && root.chosen.task === rec.modelData.task && root.chosen.item === rec.modelData.item
            width: root.width
            height: recCol.implicitHeight + 24
            radius: 16
            color: rec.on ? DrawerTheme.cardHover : DrawerTheme.card
            border.width: 1
            border.color: rec.on ? DrawerTheme.primary : DrawerTheme.clear(DrawerTheme.primary)
            Behavior on border.color { ColorAnimation { duration: 120 } }
            scale: recHit.pressed ? 0.98 : 1
            Behavior on scale { NumberAnimation { duration: 90; easing.type: Easing.OutCubic } }
            Column {
                id: recCol
                x: 14
                y: 12
                width: parent.width - 28
                spacing: 3
                Item {
                    width: parent.width
                    height: recTitle.implicitHeight
                    BoussoleText {
                        id: recTitle
                        width: parent.width - recMin.implicitWidth - 10
                        text: rec.modelData.title
                        font.pixelSize: 14
                        font.weight: Font.Bold
                        maximumLineCount: 2
                        elide: Text.ElideRight
                    }
                    BoussoleText {
                        id: recMin
                        anchors.right: parent.right
                        text: rec.modelData.minutes + " min"
                        color: DrawerTheme.secondary
                        font.pixelSize: 12
                    }
                }
                BoussoleText { width: parent.width; visible: text !== ""; text: rec.modelData.where; color: DrawerTheme.secondary; font.pixelSize: 12 }
                BoussoleText { width: parent.width; text: rec.modelData.why; color: DrawerTheme.cream2; font.pixelSize: 12 }
            }
            MouseArea {
                id: recHit
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.pick(rec.modelData)
            }
        }
    }

    // ---- or anything else in the subject ---------------------------------
    BoussoleText {
        visible: root.subjectData !== null
        text: root.b.tr("Or anything else in ", "Ou autre chose en ") + (root.subjectData ? root.subjectData.label : "")
        color: DrawerTheme.secondary
        font.pixelSize: 11
        font.weight: Font.Bold
        font.letterSpacing: 1
        font.capitalization: Font.AllUppercase
    }
    Rectangle {
        visible: root.subjectData !== null
        width: parent.width
        height: chapCol.implicitHeight
        radius: 18
        color: DrawerTheme.card
        clip: true
        Column {
            id: chapCol
            width: parent.width
            Repeater {
                model: root.subjectData ? root.subjectData.chapters : []
                delegate: Column {
                    id: chap
                    required property var modelData
                    readonly property bool unfolded: root.open[chap.modelData.id] === true
                        || (root.open[chap.modelData.id] === undefined && chap.modelData.items.some(i => i.state === "next"))
                    width: chapCol.width
                    Item {
                        width: parent.width
                        height: 46
                        Text {
                            id: chev
                            x: 14
                            anchors.verticalCenter: parent.verticalCenter
                            text: ""
                            rotation: chap.unfolded ? 90 : 0
                            Behavior on rotation { NumberAnimation { duration: 120 } }
                            color: DrawerTheme.secondary
                            font.family: Fonts.iconLucide
                            font.pixelSize: 14
                        }
                        BoussoleText {
                            anchors.left: chev.right
                            anchors.leftMargin: 10
                            anchors.right: chapCount.left
                            anchors.rightMargin: 10
                            anchors.verticalCenter: parent.verticalCenter
                            text: chap.modelData.name
                            font.pixelSize: 14
                            font.weight: Font.DemiBold
                            wrapMode: Text.NoWrap
                            elide: Text.ElideRight
                        }
                        BoussoleText {
                            id: chapCount
                            anchors.right: parent.right
                            anchors.rightMargin: 14
                            anchors.verticalCenter: parent.verticalCenter
                            text: chap.modelData.count
                            color: DrawerTheme.secondary
                            font.pixelSize: 12
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                const o = Object.assign({}, root.open);
                                o[chap.modelData.id] = !chap.unfolded;
                                root.open = o;
                            }
                        }
                    }
                    Column {
                        visible: chap.unfolded
                        x: 6
                        width: parent.width - 12
                        bottomPadding: 6
                        Repeater {
                            model: chap.unfolded ? chap.modelData.items : []
                            delegate: Rectangle {
                                id: file
                                required property var modelData
                                readonly property bool on: root.chosen !== null && root.chosen.item === file.modelData.id
                                width: parent.width
                                height: 36
                                radius: 10
                                color: file.on ? DrawerTheme.cardRaised : (fileHit.containsMouse ? DrawerTheme.cardHover : "transparent")
                                border.width: file.on ? 1 : 0
                                border.color: DrawerTheme.secondary
                                BoussoleText {
                                    id: num
                                    x: 6
                                    width: 24
                                    anchors.verticalCenter: parent.verticalCenter
                                    horizontalAlignment: Text.AlignRight
                                    text: file.modelData.num
                                    color: DrawerTheme.muted
                                    font.pixelSize: 12
                                }
                                BoussoleText {
                                    anchors.left: num.right
                                    anchors.leftMargin: 10
                                    anchors.right: fileState.left
                                    anchors.rightMargin: 10
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: LibraryState.rowsById[file.modelData.id] ? LibraryState.rowsById[file.modelData.id].title : file.modelData.title
                                    color: file.modelData.state === "read" ? DrawerTheme.secondary : DrawerTheme.primary
                                    font.pixelSize: 14
                                    wrapMode: Text.NoWrap
                                    elide: Text.ElideRight
                                }
                                BoussoleText {
                                    id: fileState
                                    anchors.right: parent.right
                                    anchors.rightMargin: 8
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: file.modelData.detail
                                    color: file.modelData.state === "next" ? DrawerTheme.primary : DrawerTheme.muted
                                    font.pixelSize: 12
                                    font.weight: file.modelData.state === "next" ? Font.DemiBold : Font.Normal
                                }
                                MouseArea {
                                    id: fileHit
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        const r = LibraryState.rowsById[file.modelData.id];
                                        if (r) root.pickRow(r);
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    BoussoleText {
        visible: root.subjectData === null && root.lib !== null
        width: parent.width
        text: root.b.tr("Pick a module to browse its files.", "Choisis un module pour parcourir ses fichiers.")
        color: DrawerTheme.secondary
        font.pixelSize: 13
    }

    // ---- any file ----------------------------------------------------------
    Rectangle {
        width: parent.width
        height: 44
        radius: 22
        color: anyHit.containsMouse ? DrawerTheme.cardHover : "transparent"
        border.width: 1
        border.color: DrawerTheme.faint
        Text {
            id: anyGlass
            x: 16
            anchors.verticalCenter: parent.verticalCenter
            text: ""
            color: DrawerTheme.secondary
            font.family: Fonts.iconLucide
            font.pixelSize: 16
        }
        BoussoleText {
            anchors.left: anyGlass.right
            anchors.leftMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            text: root.b.tr("Any course file…", "N'importe quel fichier de cours…")
            color: DrawerTheme.secondary
        }
        MouseArea {
            id: anyHit
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: LibraryState.show(root.b.activeScreen, "choose", r => root.pickRow(r))
        }
    }

    // ---- what it will be ---------------------------------------------------
    Rectangle {
        visible: root.chosen !== null
        width: parent.width
        height: sumCol.implicitHeight + 36
        radius: 22
        color: "transparent"
        border.width: 1
        border.color: DrawerTheme.faint
        Column {
            id: sumCol
            x: 18
            y: 18
            width: parent.width - 36
            spacing: 12
            Column {
                width: parent.width
                spacing: 3
                BoussoleText { width: parent.width; text: root.chosen ? root.chosen.title : ""; font.pixelSize: 16; font.weight: Font.Bold }
                BoussoleText { width: parent.width; visible: text !== ""; text: root.chosen ? root.chosen.where : ""; color: DrawerTheme.secondary; font.pixelSize: 12 }
            }
            BoussoleText { width: parent.width; text: root.verdict; color: DrawerTheme.cream2; font.pixelSize: 13 }
            Flow {
                visible: !root.school
                width: parent.width
                spacing: 6
                Repeater {
                    model: [30, 45, 60, 90].filter(m => root.span === 0 || m <= root.span)
                    delegate: BoussoleChip {
                        required property var modelData
                        text: modelData < 60 ? modelData + " min" : (modelData === 60 ? "1 h" : "1 h 30")
                        on: root.minutes === modelData
                        onClicked: root.minutes = modelData
                    }
                }
            }
            BoussolePill {
                width: parent.width
                primary: true
                text: root.b.tr("Start · ", "Commencer · ")
                      + (root.school ? root.b.tr("until ", "jusqu'à ") + root.until : (root.minutes < 60 ? root.minutes + " min" : (root.minutes === 60 ? "1 h" : "1 h 30")))
                onClicked: root.start()
            }
            BoussoleText {
                visible: root.note !== ""
                width: parent.width
                text: root.note
                color: DrawerTheme.secondary
                font.pixelSize: 12
            }
        }
    }
}
