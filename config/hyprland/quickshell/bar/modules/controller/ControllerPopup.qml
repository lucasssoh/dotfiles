import QtQuick
import Quickshell
import Quickshell.Widgets
import "../../theme"
import "../../services"

// The controller popup: what a Guide press opens. A row of large tiles
// (Steam's Big Picture, Lutris, the app grid, sleep, and turning a
// Bluetooth pad off), driven from the pad through ControllerState.nav, and
// just as well from the keyboard or the mouse. LB/RB set the volume from
// anywhere in it; the OSD shows the level as usual.
//
// Focus is an outline, not the drawers' inverted "on" fill: these tiles are
// large, and a white slab moving across them is what the shell avoids.
Item {
    id: root

    implicitWidth: card.width
    implicitHeight: card.height
    // The window stays mapped until the fade has finished (see shell.qml).
    readonly property real cardOpacity: card.opacity

    // Looked up on every opening: byId is a call, not a binding, and the
    // desktop entries are still loading when the bar starts.
    property var steamEntry: null
    property var lutrisEntry: null

    readonly property var tiles: {
        const t = [];
        if (root.steamEntry) t.push({ key: "steam", label: "Steam", icon: root.steamEntry.icon });
        if (root.lutrisEntry) t.push({ key: "lutris", label: "Lutris", icon: root.lutrisEntry.icon });
        t.push({ key: "apps", label: "Apps", glyph: "" });
        t.push({ key: "sleep", label: "Sleep", glyph: "" });
        if (ControllerState.btDevice) t.push({ key: "off", label: "Turn off", glyph: "" });
        return t;
    }
    property int focusIndex: 0

    // Built when the page opens, not at start-up: the bar never pays for a
    // list of every application unless someone asks for it.
    property var apps: []

    readonly property bool showing: ControllerState.open
    onShowingChanged: {
        if (showing) {
            root.steamEntry = DesktopEntries.byId("steam");
            root.lutrisEntry = DesktopEntries.byId("net.lutris.Lutris");
            root.focusIndex = 0;
            keys.forceActiveFocus();
        }
    }

    function activate(key) {
        if (key === "steam") ControllerState.launch(["steam", "steam://open/bigpicture"]);
        else if (key === "lutris") { root.lutrisEntry.execute(); ControllerState.close(); }
        else if (key === "apps") root.openApps();
        else if (key === "sleep") ControllerState.launch(["systemctl", "suspend"]);
        else if (key === "off") ControllerState.turnOffPad();
    }

    function openApps() {
        root.apps = DesktopEntries.applications.values
            .filter(e => !e.noDisplay && e.name)
            .sort((a, b) => a.name.localeCompare(b.name));
        appGrid.currentIndex = 0;
        ControllerState.page = "apps";
    }

    function handle(button) {
        if (ControllerState.page === "apps") {
            if (button === "left") appGrid.moveCurrentIndexLeft();
            else if (button === "right") appGrid.moveCurrentIndexRight();
            else if (button === "up") appGrid.moveCurrentIndexUp();
            else if (button === "down") appGrid.moveCurrentIndexDown();
            else if (button === "a" && root.apps[appGrid.currentIndex]) {
                root.apps[appGrid.currentIndex].execute();
                ControllerState.close();
            } else if (button === "b") ControllerState.page = "home";
            return;
        }
        if (button === "left") root.focusIndex = Math.max(0, root.focusIndex - 1);
        else if (button === "right") root.focusIndex = Math.min(root.tiles.length - 1, root.focusIndex + 1);
        else if (button === "a" && root.tiles[root.focusIndex]) root.activate(root.tiles[root.focusIndex].key);
        else if (button === "b") ControllerState.close();
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
                [Qt.Key_Escape]: "b", [Qt.Key_Backspace]: "b",
            };
            if (map[event.key] !== undefined) {
                root.handle(map[event.key]);
                event.accepted = true;
            }
        }
    }

    // ---- card --------------------------------------------------------
    Rectangle {
        id: card
        width: 24 * 2 + Math.max(tileRow.width, 5 * 112 + 4 * 12)
        height: column.height + 24 * 2
        radius: 32
        color: DrawerTheme.panelTop
        border.width: 1
        border.color: DrawerTheme.ink(0.08)

        opacity: root.showing ? 1 : 0
        scale: root.showing ? 1 : 0.94
        Behavior on opacity { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
        Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

        Column {
            id: column
            x: 24
            y: 24
            width: card.width - 48
            spacing: 20

            // ---- header: the pad, its battery, the volume -------------
            Item {
                width: parent.width
                height: 40

                Rectangle {
                    id: badge
                    width: 40
                    height: 40
                    radius: 14
                    color: DrawerTheme.card
                    Text {
                        anchors.centerIn: parent
                        renderType: Text.NativeRendering
                        text: ""
                        color: DrawerTheme.primary
                        font.family: Fonts.iconMingcute
                        font.pixelSize: 20
                    }
                }
                Column {
                    anchors.left: badge.right
                    anchors.leftMargin: 12
                    anchors.right: volume.left
                    anchors.rightMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 1
                    Text {
                        width: parent.width
                        renderType: Text.NativeRendering
                        text: ControllerState.page === "apps" ? "Apps" : (ControllerState.pad ? ControllerState.pad.name : "Controller")
                        color: DrawerTheme.primary
                        font.family: Fonts.ui
                        font.pixelSize: 15
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                    }
                    Text {
                        width: parent.width
                        renderType: Text.NativeRendering
                        text: {
                            const p = ControllerState.pad;
                            if (!p) return "";
                            const parts = [p.bus === "bluetooth" ? "Bluetooth" : p.bus === "usb" ? "USB" : "Connected"];
                            if (ControllerState.battery !== null) parts.push(ControllerState.battery + " %" + (p.charging ? ", charging" : ""));
                            return parts.join(" · ");
                        }
                        color: DrawerTheme.secondary
                        font.family: Fonts.ui
                        font.pixelSize: 12
                        elide: Text.ElideRight
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

            // ---- home: the tiles --------------------------------------
            Row {
                id: tileRow
                visible: ControllerState.page === "home"
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 12
                Repeater {
                    model: root.tiles
                    Tile {
                        required property var modelData
                        required property int index
                        label: modelData.label
                        icon: modelData.icon || ""
                        glyph: modelData.glyph || ""
                        focused: root.focusIndex === index
                        onHovered: root.focusIndex = index
                        onClicked: root.activate(modelData.key)
                    }
                }
            }

            // ---- apps: every application, in a grid -------------------
            GridView {
                id: appGrid
                visible: ControllerState.page === "apps"
                width: parent.width
                height: 3 * cellHeight
                cellWidth: Math.floor(width / 5)
                cellHeight: 112
                clip: true
                model: root.apps
                keyNavigationWraps: false
                highlightMoveDuration: 0
                preferredHighlightBegin: 0
                preferredHighlightEnd: height
                highlightRangeMode: GridView.ApplyRange
                delegate: Item {
                    required property var modelData
                    required property int index
                    width: appGrid.cellWidth
                    height: appGrid.cellHeight
                    Tile {
                        anchors.centerIn: parent
                        width: parent.width - 12
                        height: parent.height - 12
                        label: modelData.name
                        icon: modelData.icon || ""
                        glyph: ""
                        focused: appGrid.currentIndex === index
                        onHovered: appGrid.currentIndex = index
                        onClicked: { modelData.execute(); ControllerState.close(); }
                    }
                }
            }

            // ---- what the buttons do ----------------------------------
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 18
                Row {
                    spacing: 7
                    FaceButton {
                        anchors.verticalCenter: parent.verticalCenter
                        kind: ControllerState.labels.south.kind
                        label: ControllerState.labels.south.label
                        tint: ControllerState.labels.south.tint
                        pos: "s"
                    }
                    HintText { text: "Open" }
                }
                Row {
                    spacing: 7
                    FaceButton {
                        anchors.verticalCenter: parent.verticalCenter
                        kind: ControllerState.labels.east.kind
                        label: ControllerState.labels.east.label
                        tint: ControllerState.labels.east.tint
                        pos: "e"
                    }
                    HintText { text: ControllerState.page === "apps" ? "Back" : "Close" }
                }
            }
        }
    }

    // ---- pieces --------------------------------------------------------
    component Tile: Rectangle {
        id: tile
        property string label: ""
        property string icon: ""
        property string glyph: ""
        property bool focused: false
        signal hovered()
        signal clicked()

        readonly property string iconSource: tile.icon !== "" ? Quickshell.iconPath(tile.icon, true) : ""

        width: 112
        height: 120
        radius: 22
        color: tile.focused ? DrawerTheme.cardRaised : DrawerTheme.card
        border.width: 2
        border.color: tile.focused ? DrawerTheme.primary : "transparent"
        scale: tile.focused ? 1.04 : 1
        Behavior on color { ColorAnimation { duration: 100 } }
        Behavior on scale { NumberAnimation { duration: 100; easing.type: Easing.OutCubic } }

        IconImage {
            visible: tile.iconSource !== ""
            anchors.horizontalCenter: parent.horizontalCenter
            y: tile.height * 0.2
            implicitSize: 44
            source: tile.iconSource
        }
        Text {
            visible: tile.iconSource === ""
            anchors.horizontalCenter: parent.horizontalCenter
            y: tile.height * 0.2 + 4
            renderType: Text.NativeRendering
            text: tile.glyph
            color: DrawerTheme.primary
            font.family: Fonts.iconMingcute
            font.pixelSize: 34
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 14
            width: parent.width - 16
            horizontalAlignment: Text.AlignHCenter
            renderType: Text.NativeRendering
            text: tile.label
            color: tile.focused ? DrawerTheme.primary : DrawerTheme.secondary
            font.family: Fonts.ui
            font.pixelSize: 13
            font.weight: Font.DemiBold
            elide: Text.ElideRight
        }
        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onEntered: tile.hovered()
            onClicked: tile.clicked()
        }
    }

    component HintText: Text {
        anchors.verticalCenter: parent ? parent.verticalCenter : undefined
        renderType: Text.NativeRendering
        color: DrawerTheme.secondary
        font.family: Fonts.ui
        font.pixelSize: 12
    }
}
