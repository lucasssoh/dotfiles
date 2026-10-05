import QtQuick
import Quickshell
import Quickshell.Widgets
import "../../theme"
import "../../services"

// The controller popup: what a Guide press opens. Built each time it opens
// and destroyed once it has faded (shell.qml's Loader), so nothing here
// exists while the popup is closed.
//
// Home, top to bottom, one focus row each:
//   - Continue: the game played last, large, from the daemon's library;
//   - Library: the games after it, Steam and Lutris read by the daemon,
//     every other launcher's games through their "Game" desktop entries;
//   - Launchers: the ones installed, Steam opening in Big Picture;
//   - System: the app grid, sleep, and turning a Bluetooth pad off.
// Y opens the full grid, where LT/RT step through the tabs (All, Games,
// then one per source) and X jumps to the next letter. LB/RB set the volume
// from anywhere (ControllerState). The keyboard and the mouse drive it all
// the same way.
//
// Focus is an outline, not the drawers' inverted "on" fill: these cards are
// large, and a white slab moving across them is what the shell avoids.
Item {
    id: root

    implicitWidth: card.width
    implicitHeight: card.height
    readonly property real cardOpacity: card.opacity

    // ---- what there is to show ------------------------------------------

    // Desktop entries are read once, when the popup is built.
    property var launchers: []
    property var desktopGames: []
    property var apps: []

    readonly property var games: ControllerState.games.concat(root.desktopGames)
    readonly property var hero: {
        const g = ControllerState.games;
        return g.length > 0 && g[0].last > 0 ? g[0] : null;
    }
    readonly property var shelf: root.games.filter(g => g !== root.hero).slice(0, 6)
    readonly property var system: {
        const t = [{ key: "apps", label: "Apps", glyph: "" }, { key: "sleep", label: "Sleep", glyph: "" }];
        if (ControllerState.btDevice) t.push({ key: "off", label: "Turn off", glyph: "" });
        return t;
    }

    // The rows of the home page that have something in them, as they sit
    // on screen: Launchers and System share one line, so they are one row,
    // the launchers first, and left/right walks from one into the other.
    readonly property var rows: {
        const r = [];
        if (root.hero) r.push("hero");
        if (root.shelf.length > 0) r.push("shelf");
        r.push("bottom");
        return r;
    }
    property int row: 0
    property var col: ({ hero: 0, shelf: 0, bottom: 0 })
    readonly property string rowName: root.rows[Math.min(root.row, root.rows.length - 1)]
    function lengthOf(name) {
        return name === "hero" ? 1 : name === "shelf" ? root.shelf.length
             : root.launchers.length + root.system.length;
    }
    function focused(name, i) {
        return ControllerState.page === "home" && root.rowName === name && root.col[name] === i;
    }
    function focus(name, i) {
        const r = root.rows.indexOf(name);
        if (r < 0) return;
        root.row = r;
        const c = Object.assign({}, root.col);
        c[name] = i;
        root.col = c;
    }

    // Grid tabs: All, Games, then one per source that has games.
    readonly property var tabs: {
        const t = [{ name: "All", items: root.apps.concat(root.games.map(root.asTile)).sort(root.byName) },
                   { name: "Games", items: root.games.map(root.asTile).sort(root.byName) }];
        const seen = [];
        root.games.forEach(g => { if (seen.indexOf(g.source) < 0) seen.push(g.source); });
        seen.forEach(s => t.push({ name: s, items: root.games.filter(g => g.source === s).map(root.asTile).sort(root.byName) }));
        return t;
    }
    property int tab: 0
    readonly property var gridItems: root.tabs[Math.min(root.tab, root.tabs.length - 1)].items

    function byName(a, b) { return a.name.localeCompare(b.name); }
    function asTile(g) {
        return { name: g.title, icon: g.icon || "", cover: g.cover || "", source: g.source, game: g };
    }

    // ---- reading the desktop entries ------------------------------------

    readonly property var launcherDefs: [
        { ids: ["steam", "com.valvesoftware.Steam"], name: "Steam", sub: "Big Picture", argv: ["steam", "steam://open/bigpicture"] },
        { ids: ["net.lutris.Lutris"], name: "Lutris", source: "Lutris" },
        { ids: ["com.heroicgameslauncher.hgl", "heroic"], name: "Heroic", sub: "Epic · GOG · Amazon" },
        { ids: ["com.usebottles.bottles"], name: "Bottles", sub: "Windows apps" },
        { ids: ["io.itch.itch", "itch"], name: "itch", sub: "itch.io" }
    ]

    Component.onCompleted: {
        const all = DesktopEntries.applications.values.filter(e => !e.noDisplay && e.name);
        const launcherIds = [];
        const found = [];
        root.launcherDefs.forEach(d => {
            for (const id of d.ids) {
                const e = DesktopEntries.byId(id);
                if (e) { found.push({ def: d, entry: e }); launcherIds.push(e.id); break; }
            }
        });
        root.launchers = found;

        // Games other launchers put in the menu (Heroic, Bottles, itch,
        // emulators…). Steam and Lutris shortcuts are left out: the daemon
        // already lists those games, with their artwork.
        root.desktopGames = all
            .filter(e => root.isGame(e) && launcherIds.indexOf(e.id) < 0)
            .filter(e => !/steam:\/\/rungameid|lutris:rungameid/.test((e.command || []).join(" ") + " " + (e.execString || "")))
            .map(e => ({ id: "desktop:" + e.id, title: e.name, source: root.sourceOf(e), last: 0, icon: e.icon, entry: e }));

        root.apps = all
            .filter(e => !root.isGame(e) || launcherIds.indexOf(e.id) >= 0)
            .map(e => ({ name: e.name, icon: e.icon || "", cover: "", source: "", entry: e }));

        keys.forceActiveFocus();
    }

    // A game, as opposed to a tool for games, which also files itself under
    // "Game": by its other categories, or by name for the ones that say
    // nothing else (GOverlay, which the mangohud unit installs).
    readonly property var gameTools: ["io.github.benjamimgois.goverlay"]
    function isGame(e) {
        const c = e.categories || [];
        return c.indexOf("Game") >= 0 && root.gameTools.indexOf(e.id) < 0
            && !c.some(x => x === "Utility" || x === "Settings" || x === "System");
    }
    // Which launcher a game's desktop entry runs through.
    function sourceOf(e) {
        const cmd = ((e.command || []).join(" ") + " " + (e.execString || "")).toLowerCase();
        if (cmd.indexOf("heroic") >= 0) return "Heroic";
        if (cmd.indexOf("bottles") >= 0) return "Bottles";
        if (cmd.indexOf("itch") >= 0) return "itch";
        return "Other";
    }

    // ---- actions --------------------------------------------------------

    function play(g) {
        if (g.launch) ControllerState.launchGame(g.launch);
        else if (g.entry) { g.entry.execute(); ControllerState.close(); }
    }
    function openLauncher(l) {
        // Steam, Lutris, Heroic: game launchers, asked about during a session.
        if (l.def.argv) {
            if (/steam|lutris|heroic/.test(l.def.argv.join(" ").toLowerCase())) ControllerState.launchGame(l.def.argv);
            else ControllerState.launch(l.def.argv);
        }
        else { l.entry.execute(); ControllerState.close(); }
    }
    function runSystem(key) {
        if (key === "apps") { root.tab = 0; appGrid.currentIndex = 0; ControllerState.page = "apps"; }
        else if (key === "sleep") ControllerState.launch(["systemctl", "suspend"]);
        else if (key === "off") ControllerState.turnOffPad();
    }
    function openTile(t) {
        if (t.game) root.play(t.game);
        else { t.entry.execute(); ControllerState.close(); }
    }

    function handle(button) {
        if (ControllerState.page === "confirm") {
            if (button === "a") ControllerState.confirmLaunch();
            else if (button === "b") ControllerState.close();
            return;
        }
        if (ControllerState.page === "apps") {
            if (button === "left") appGrid.moveCurrentIndexLeft();
            else if (button === "right") appGrid.moveCurrentIndexRight();
            else if (button === "up") appGrid.moveCurrentIndexUp();
            else if (button === "down") appGrid.moveCurrentIndexDown();
            else if (button === "lt") { root.tab = (root.tab + root.tabs.length - 1) % root.tabs.length; appGrid.currentIndex = 0; }
            else if (button === "rt") { root.tab = (root.tab + 1) % root.tabs.length; appGrid.currentIndex = 0; }
            else if (button === "x") root.nextLetter();
            else if (button === "a" && root.gridItems[appGrid.currentIndex]) root.openTile(root.gridItems[appGrid.currentIndex]);
            else if (button === "b") ControllerState.page = "home";
            return;
        }
        const name = root.rowName;
        if (button === "up") root.row = Math.max(0, root.row - 1);
        else if (button === "down") root.row = Math.min(root.rows.length - 1, root.row + 1);
        else if (button === "left" || button === "right") {
            const c = Object.assign({}, root.col);
            c[name] = Math.max(0, Math.min(root.lengthOf(name) - 1, c[name] + (button === "left" ? -1 : 1)));
            root.col = c;
        }
        else if (button === "y") root.runSystem("apps");
        else if (button === "b") ControllerState.close();
        else if (button === "a") {
            const i = root.col[name];
            if (name === "hero") root.play(root.hero);
            else if (name === "shelf") root.play(root.shelf[i]);
            else if (i < root.launchers.length) root.openLauncher(root.launchers[i]);
            else root.runSystem(root.system[i - root.launchers.length].key);
        }
    }

    // X in the grid: the first item whose name starts after the current one's letter.
    function nextLetter() {
        const items = root.gridItems;
        if (items.length === 0) return;
        const here = (items[appGrid.currentIndex] || items[0]).name.charAt(0).toUpperCase();
        const i = items.findIndex(t => t.name.charAt(0).toUpperCase() > here);
        appGrid.currentIndex = i < 0 ? 0 : i;
    }

    Connections {
        target: ControllerState
        function onNav(button) { root.handle(button); }
    }

    Item {
        id: keys
        focus: true
        Keys.onPressed: (event) => {
            const map = {
                [Qt.Key_Left]: "left", [Qt.Key_Right]: "right", [Qt.Key_Up]: "up", [Qt.Key_Down]: "down",
                [Qt.Key_Return]: "a", [Qt.Key_Enter]: "a", [Qt.Key_Space]: "a",
                [Qt.Key_Escape]: "b", [Qt.Key_Backspace]: "b", [Qt.Key_Tab]: "rt", [Qt.Key_Backtab]: "lt",
            };
            if (map[event.key] !== undefined) {
                root.handle(map[event.key]);
                event.accepted = true;
            }
        }
    }

    // ---- card -----------------------------------------------------------

    Rectangle {
        id: card
        width: 940
        height: column.height + 26 * 2
        radius: 34
        color: DrawerTheme.panelTop
        border.width: 1
        border.color: DrawerTheme.ink(0.08)

        opacity: ControllerState.open ? 1 : 0
        scale: ControllerState.open ? 1 : 0.96
        Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
        Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

        Column {
            id: column
            x: 26
            y: 26
            width: card.width - 52
            spacing: 20

            // ---- header -------------------------------------------------
            Item {
                width: parent.width
                height: 42

                Rectangle {
                    id: badge
                    width: 42
                    height: 42
                    radius: 14
                    color: DrawerTheme.card
                    PadSilhouette {
                        anchors.centerIn: parent
                        width: 24
                        height: 16
                        level: 100
                    }
                }
                Column {
                    anchors.left: badge.right
                    anchors.leftMargin: 12
                    anchors.right: volume.left
                    anchors.rightMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 3
                    Text {
                        width: parent.width
                        renderType: Text.NativeRendering
                        text: ControllerState.page === "apps" ? "Apps and games" : (ControllerState.pad ? ControllerState.pad.name : "Controller")
                        color: DrawerTheme.primary
                        font.family: Fonts.ui
                        font.pixelSize: 15
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                    }
                    Row {
                        spacing: 7
                        visible: ControllerState.page === "home" && ControllerState.pad !== null
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            renderType: Text.NativeRendering
                            text: !ControllerState.pad ? "" : ControllerState.pad.bus === "bluetooth" ? "Bluetooth" : ControllerState.pad.bus === "usb" ? "USB" : "Connected"
                            color: DrawerTheme.secondary
                            font.family: Fonts.ui
                            font.pixelSize: 12
                        }
                        PadSilhouette {
                            visible: ControllerState.battery !== null
                            anchors.verticalCenter: parent.verticalCenter
                            width: 18
                            height: 12
                            level: ControllerState.battery
                            charging: ControllerState.pad ? ControllerState.pad.charging : false
                        }
                        Text {
                            visible: ControllerState.battery !== null
                            anchors.verticalCenter: parent.verticalCenter
                            renderType: Text.NativeRendering
                            text: ControllerState.battery + " %"
                            color: DrawerTheme.secondary
                            font.family: Fonts.ui
                            font.pixelSize: 12
                        }
                    }
                    // The tabs, on the grid page.
                    Row {
                        spacing: 6
                        visible: ControllerState.page === "apps"
                        Repeater {
                            model: root.tabs
                            Rectangle {
                                required property var modelData
                                required property int index
                                readonly property bool on: index === root.tab
                                width: tabLabel.implicitWidth + 20
                                height: 24
                                radius: 12
                                color: on ? DrawerTheme.cardRaised : "transparent"
                                border.width: on ? 1.5 : 0
                                border.color: DrawerTheme.primary
                                Text {
                                    id: tabLabel
                                    anchors.centerIn: parent
                                    renderType: Text.NativeRendering
                                    text: modelData.name + "  " + modelData.items.length
                                    color: parent.on ? DrawerTheme.primary : DrawerTheme.secondary
                                    font.family: Fonts.ui
                                    font.pixelSize: 12
                                    font.weight: Font.DemiBold
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: { root.tab = index; appGrid.currentIndex = 0; }
                                }
                            }
                        }
                    }
                }
                Row {
                    id: volume
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 8
                    ShoulderButton { label: ControllerState.labels.lb }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        renderType: Text.NativeRendering
                        text: ""
                        color: DrawerTheme.secondary
                        font.family: Fonts.iconMingcute
                        font.pixelSize: 15
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 26
                        renderType: Text.NativeRendering
                        text: Math.round(ControllerState.volume * 100)
                        color: DrawerTheme.primary
                        font.family: Fonts.ui
                        font.pixelSize: 13
                        font.weight: Font.DemiBold
                        font.features: { "tnum": 1 }
                        horizontalAlignment: Text.AlignHCenter
                    }
                    ShoulderButton { label: ControllerState.labels.rb }
                }
            }

            // ---- home: Continue ----------------------------------------
            Rectangle {
                id: heroCard
                visible: ControllerState.page === "home" && root.hero !== null
                readonly property bool on: root.focused("hero", 0)
                width: parent.width
                height: 196
                radius: 26
                color: on ? DrawerTheme.cardRaised : DrawerTheme.card
                border.width: 2
                border.color: on ? DrawerTheme.primary : "transparent"

                ClippingRectangle {
                    x: 14
                    y: 14
                    width: 300
                    height: parent.height - 28
                    radius: 18
                    color: DrawerTheme.cardRaised
                    Image {
                        anchors.fill: parent
                        source: root.hero && root.hero.hero ? "file://" + root.hero.hero : ""
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        sourceSize.width: 600
                    }
                }
                Column {
                    x: 14 + 300 + 24
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - x - 20
                    spacing: 10
                    Text {
                        renderType: Text.NativeRendering
                        text: "CONTINUE"
                        color: DrawerTheme.secondary
                        font.family: Fonts.ui
                        font.pixelSize: 12
                        font.weight: Font.Bold
                        font.letterSpacing: 0.8
                    }
                    Text {
                        width: parent.width
                        renderType: Text.NativeRendering
                        text: root.hero ? root.hero.title : ""
                        color: DrawerTheme.primary
                        font.family: Fonts.ui
                        font.pixelSize: 26
                        font.weight: Font.Bold
                        elide: Text.ElideRight
                    }
                    Row {
                        spacing: 8
                        SourceChip { label: root.hero ? root.hero.source : "" }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            renderType: Text.NativeRendering
                            text: root.hero ? root.since(root.hero.last) : ""
                            color: DrawerTheme.secondary
                            font.family: Fonts.ui
                            font.pixelSize: 13
                        }
                    }
                    Row {
                        spacing: 7
                        topPadding: 6
                        FaceButton {
                            anchors.verticalCenter: parent.verticalCenter
                            kind: ControllerState.labels.south.kind
                            label: ControllerState.labels.south.label
                            tint: ControllerState.labels.south.tint
                            pos: "s"
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            renderType: Text.NativeRendering
                            text: "Play"
                            color: DrawerTheme.primary
                            font.family: Fonts.ui
                            font.pixelSize: 13
                            font.weight: Font.Bold
                        }
                    }
                }
                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onEntered: root.focus("hero", 0)
                    onClicked: root.play(root.hero)
                }
            }

            // ---- home: Library -----------------------------------------
            Column {
                visible: ControllerState.page === "home" && root.shelf.length > 0
                width: parent.width
                spacing: 12
                SectionLabel { text: "Library" }
                Row {
                    spacing: 12
                    Repeater {
                        model: root.shelf
                        Rectangle {
                            id: coverCard
                            required property var modelData
                            required property int index
                            readonly property bool on: root.focused("shelf", index)
                            width: 136
                            height: 210
                            radius: 18
                            color: on ? DrawerTheme.cardRaised : DrawerTheme.card
                            border.width: 2
                            border.color: on ? DrawerTheme.primary : "transparent"
                            scale: on ? 1.04 : 1
                            Behavior on scale { NumberAnimation { duration: 100; easing.type: Easing.OutCubic } }

                            ClippingRectangle {
                                x: 6
                                y: 6
                                width: parent.width - 12
                                height: 160
                                radius: 13
                                color: DrawerTheme.cardRaised
                                Image {
                                    visible: !!coverCard.modelData.cover
                                    anchors.fill: parent
                                    source: coverCard.modelData.cover ? "file://" + coverCard.modelData.cover : ""
                                    fillMode: Image.PreserveAspectCrop
                                    asynchronous: true
                                    sourceSize.width: 256
                                }
                                IconImage {
                                    visible: !coverCard.modelData.cover
                                    anchors.centerIn: parent
                                    implicitSize: 56
                                    source: coverCard.modelData.icon ? Quickshell.iconPath(coverCard.modelData.icon, true) : ""
                                }
                                SourceChip {
                                    x: 7
                                    y: parent.height - height - 7
                                    label: coverCard.modelData.source
                                    dark: true
                                }
                            }
                            Text {
                                x: 10
                                y: 172
                                width: parent.width - 20
                                renderType: Text.NativeRendering
                                text: coverCard.modelData.title
                                color: coverCard.on ? DrawerTheme.primary : DrawerTheme.secondary
                                font.family: Fonts.ui
                                font.pixelSize: 12
                                font.weight: Font.DemiBold
                                elide: Text.ElideRight
                            }
                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onEntered: root.focus("shelf", coverCard.index)
                                onClicked: root.play(coverCard.modelData)
                            }
                        }
                    }
                }
            }

            // ---- home: Launchers and System -----------------------------
            Row {
                visible: ControllerState.page === "home"
                width: parent.width
                spacing: 24

                Column {
                    visible: root.launchers.length > 0
                    spacing: 12
                    SectionLabel { text: "Launchers" }
                    Row {
                        spacing: 10
                        Repeater {
                            model: root.launchers
                            Rectangle {
                                id: launcherCard
                                required property var modelData
                                required property int index
                                readonly property bool on: root.focused("bottom", index)
                                width: Math.max(150, launcherText.implicitWidth + 30 + 34 + 24)
                                height: 56
                                radius: 16
                                color: on ? DrawerTheme.cardRaised : DrawerTheme.card
                                border.width: 2
                                border.color: on ? DrawerTheme.primary : "transparent"
                                IconImage {
                                    x: 12
                                    anchors.verticalCenter: parent.verticalCenter
                                    implicitSize: 30
                                    source: Quickshell.iconPath(launcherCard.modelData.entry.icon || "", true)
                                }
                                Column {
                                    id: launcherText
                                    x: 12 + 30 + 10
                                    anchors.verticalCenter: parent.verticalCenter
                                    Text {
                                        renderType: Text.NativeRendering
                                        text: launcherCard.modelData.def.name
                                        color: DrawerTheme.primary
                                        font.family: Fonts.ui
                                        font.pixelSize: 13
                                        font.weight: Font.Bold
                                    }
                                    Text {
                                        renderType: Text.NativeRendering
                                        text: launcherCard.modelData.def.source
                                            ? ControllerState.games.filter(g => g.source === launcherCard.modelData.def.source).length + " games"
                                            : (launcherCard.modelData.def.sub || "")
                                        color: DrawerTheme.secondary
                                        font.family: Fonts.ui
                                        font.pixelSize: 11
                                    }
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onEntered: root.focus("bottom", launcherCard.index)
                                    onClicked: root.openLauncher(launcherCard.modelData)
                                }
                            }
                        }
                    }
                }

                Column {
                    spacing: 12
                    SectionLabel { text: "System" }
                    Row {
                        spacing: 10
                        Repeater {
                            model: root.system
                            Rectangle {
                                id: sysCard
                                required property var modelData
                                required property int index
                                readonly property bool on: root.focused("bottom", root.launchers.length + index)
                                width: sysRow.implicitWidth + 32
                                height: 56
                                radius: 16
                                color: on ? DrawerTheme.cardRaised : DrawerTheme.card
                                border.width: 2
                                border.color: on ? DrawerTheme.primary : "transparent"
                                Row {
                                    id: sysRow
                                    anchors.centerIn: parent
                                    spacing: 8
                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        renderType: Text.NativeRendering
                                        text: sysCard.modelData.glyph
                                        color: DrawerTheme.primary
                                        font.family: Fonts.iconMingcute
                                        font.pixelSize: 17
                                    }
                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        renderType: Text.NativeRendering
                                        text: sysCard.modelData.label
                                        color: sysCard.on ? DrawerTheme.primary : DrawerTheme.secondary
                                        font.family: Fonts.ui
                                        font.pixelSize: 13
                                        font.weight: Font.Bold
                                    }
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onEntered: root.focus("bottom", root.launchers.length + sysCard.index)
                                    onClicked: root.runSystem(sysCard.modelData.key)
                                }
                            }
                        }
                    }
                }
            }

            // ---- apps: the grid -----------------------------------------
            GridView {
                id: appGrid
                visible: ControllerState.page === "apps"
                width: parent.width
                height: 3 * cellHeight
                cellWidth: Math.floor(width / 7)
                cellHeight: 132
                clip: true
                model: root.gridItems
                keyNavigationWraps: false
                highlightMoveDuration: 0
                preferredHighlightBegin: 0
                preferredHighlightEnd: height
                highlightRangeMode: GridView.ApplyRange
                delegate: Item {
                    id: cell
                    required property var modelData
                    required property int index
                    readonly property bool on: appGrid.currentIndex === index
                    width: appGrid.cellWidth
                    height: appGrid.cellHeight
                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: 6
                        radius: 22
                        color: cell.on ? DrawerTheme.cardRaised : DrawerTheme.card
                        border.width: 2
                        border.color: cell.on ? DrawerTheme.primary : "transparent"
                        scale: cell.on ? 1.04 : 1
                        Column {
                            anchors.centerIn: parent
                            width: parent.width - 16
                            spacing: 8
                            Item {
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: 52
                                height: 52
                                ClippingRectangle {
                                    visible: cell.modelData.cover !== ""
                                    anchors.fill: parent
                                    radius: 14
                                    color: DrawerTheme.cardRaised
                                    Image {
                                        anchors.fill: parent
                                        source: cell.modelData.cover ? "file://" + cell.modelData.cover : ""
                                        fillMode: Image.PreserveAspectCrop
                                        asynchronous: true
                                        sourceSize.width: 104
                                    }
                                }
                                IconImage {
                                    visible: cell.modelData.cover === ""
                                    anchors.centerIn: parent
                                    implicitSize: 48
                                    source: cell.modelData.icon ? Quickshell.iconPath(cell.modelData.icon, true) : ""
                                }
                            }
                            Text {
                                width: parent.width
                                horizontalAlignment: Text.AlignHCenter
                                renderType: Text.NativeRendering
                                text: cell.modelData.name
                                color: cell.on ? DrawerTheme.primary : DrawerTheme.secondary
                                font.family: Fonts.ui
                                font.pixelSize: 12
                                font.weight: Font.DemiBold
                                elide: Text.ElideRight
                            }
                            Text {
                                // Per-source tabs say it already.
                                visible: cell.modelData.source !== "" && root.tab < 2
                                width: parent.width
                                horizontalAlignment: Text.AlignHCenter
                                renderType: Text.NativeRendering
                                text: cell.modelData.source
                                color: DrawerTheme.muted
                                font.family: Fonts.ui
                                font.pixelSize: 10
                                font.weight: Font.DemiBold
                            }
                        }
                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onEntered: appGrid.currentIndex = cell.index
                            onClicked: root.openTile(cell.modelData)
                        }
                    }
                }
            }

            // ---- a game during a Boussole session ------------------------
            Column {
                visible: ControllerState.page === "confirm"
                width: parent.width
                spacing: 10
                topPadding: 10
                bottomPadding: 10
                Text {
                    width: parent.width
                    renderType: Text.NativeRendering
                    text: BoussoleState.lockText
                    color: DrawerTheme.primary
                    font.family: Fonts.ui
                    font.pixelSize: 20
                    font.weight: Font.DemiBold
                    wrapMode: Text.WordWrap
                }
                Text {
                    width: parent.width
                    renderType: Text.NativeRendering
                    text: BoussoleState.tr("Launch anyway? The session waits, its time is not counted while you play.",
                                           "Lancer quand même ? La séance attend, son temps n'est pas compté pendant que tu joues.")
                    color: DrawerTheme.secondary
                    font.family: Fonts.ui
                    font.pixelSize: 15
                    wrapMode: Text.WordWrap
                }
            }

            // ---- what the buttons do ------------------------------------
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 20
                Hint {
                    face: ControllerState.labels.south; pos: "s"
                    text: ControllerState.page === "confirm" ? BoussoleState.tr("Launch anyway", "Lancer quand même") : "Open"
                }
                Hint {
                    face: ControllerState.labels.east; pos: "e"
                    text: ControllerState.page === "confirm" ? BoussoleState.tr("Back to the session", "Retour à la séance")
                        : ControllerState.page === "apps" ? "Back" : "Close"
                }
                Hint { visible: ControllerState.page === "home"; face: ControllerState.labels.north; pos: "n"; text: "All games and apps" }
                Row {
                    visible: ControllerState.page === "apps"
                    spacing: 6
                    ShoulderButton { label: ControllerState.labels.lt }
                    ShoulderButton { label: ControllerState.labels.rt }
                    HintText { text: "Tabs" }
                }
                Hint { visible: ControllerState.page === "apps"; face: ControllerState.labels.west; pos: "w"; text: "Next letter" }
            }
        }
    }

    // "Played yesterday", "Played 3 days ago"…, from a Unix time.
    function since(t) {
        if (!t) return "";
        const days = Math.floor((Date.now() / 1000 - t) / 86400);
        if (days <= 0) return "Played today";
        if (days === 1) return "Played yesterday";
        if (days < 30) return "Played " + days + " days ago";
        return "Played " + Qt.formatDate(new Date(t * 1000), "d MMM yyyy");
    }

    // ---- pieces ---------------------------------------------------------

    component SectionLabel: Text {
        renderType: Text.NativeRendering
        color: DrawerTheme.ink(0.75)
        font.family: Fonts.ui
        font.pixelSize: 13
        font.weight: Font.Bold
    }

    component SourceChip: Rectangle {
        property string label: ""
        property bool dark: false
        width: chipText.implicitWidth + 16
        height: 20
        radius: 10
        color: dark ? Qt.rgba(0, 0, 0, 0.6) : DrawerTheme.card
        Text {
            id: chipText
            anchors.centerIn: parent
            renderType: Text.NativeRendering
            text: parent.label
            color: DrawerTheme.ink(0.75)
            font.family: Fonts.ui
            font.pixelSize: 10
            font.weight: Font.Bold
        }
    }

    component Hint: Row {
        property var face
        property string pos: "s"
        property alias text: hintText.text
        spacing: 7
        FaceButton {
            anchors.verticalCenter: parent.verticalCenter
            kind: parent.face ? parent.face.kind : "letter"
            label: parent.face ? parent.face.label : ""
            tint: parent.face ? parent.face.tint : DrawerTheme.primary
            pos: parent.pos
        }
        HintText { id: hintText }
    }

    component HintText: Text {
        anchors.verticalCenter: parent ? parent.verticalCenter : undefined
        renderType: Text.NativeRendering
        color: DrawerTheme.secondary
        font.family: Fonts.ui
        font.pixelSize: 12
    }
}
