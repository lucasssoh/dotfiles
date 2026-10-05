import QtQuick
import ".."
import "../../theme"
import "../../services"

// Boussole's alert, in the central island like Veille's pulse: the start of
// a session, its reminder, "still on the exercises?", "close it?". The hour
// large and thin, what it is about, and the buttons; it stays until one is
// pressed. The handle closes it without an answer (the reminder will come).
//
// Same entry contract as VeilleDrawerContent: the caller binds
// `drawerOpen`, the island animates `height` up to `implicitHeight`. Unlike
// Veille's, the whole card takes clicks: shell.qml opens the island's
// input mask over `hit*` while it shows.
Item {
    id: root

    property bool drawerOpen: false
    Behavior on height {
        NumberAnimation { duration: 320; easing.type: Easing.InOutCubic }
    }

    readonly property var a: BoussoleState.shownAlert
    // Answered: what was done, in place of the buttons.
    readonly property bool answered: BoussoleState.acked !== null
    readonly property int hPad: 24
    readonly property int drawerWidth: 840
    readonly property real textWidth: Math.max(0, Math.min(root.width, root.drawerWidth) - root.hPad * 2)
    readonly property real contentInset: root.hPad + Math.max(0, (root.width - root.textWidth - root.hPad * 2) / 2)

    implicitHeight: handle.implicitHeight + 10 + content.implicitHeight + 24

    readonly property int hitX: 0
    readonly property int hitY: 0
    readonly property int hitWidth: root.width
    readonly property int hitHeight: root.height

    DrawerHandle {
        id: handle
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: 120
        tint: DrawerTheme.islandAccent
        onCloseRequested: BoussoleState.answer("dismiss")
    }

    Column {
        id: content
        x: root.contentInset
        anchors.top: handle.bottom
        anchors.topMargin: 10
        width: root.textWidth
        spacing: 12

        Row {
            spacing: 14
            Text {
                id: hour
                text: root.a ? root.a.time : ""
                color: DrawerTheme.cream
                font.family: Fonts.ui
                font.pixelSize: 104
                font.weight: Font.ExtraLight
                font.letterSpacing: -2
                font.features: { "tnum": 1 }
                renderType: Text.NativeRendering
                font.hintingPreference: Font.PreferNoHinting
            }
            Text {
                visible: root.a !== null && root.a.until !== undefined
                anchors.baseline: hour.baseline
                text: root.a && root.a.until ? "→ " + root.a.until : ""
                color: DrawerTheme.creamInk(0.45)
                font.family: Fonts.ui
                font.pixelSize: 30
                font.weight: Font.Light
                font.features: { "tnum": 1 }
                renderType: Text.NativeRendering
                font.hintingPreference: Font.PreferNoHinting
            }
        }

        Text {
            width: parent.width
            text: root.a ? root.a.title : ""
            color: DrawerTheme.cream
            wrapMode: Text.WordWrap
            font.family: Fonts.ui
            font.pixelSize: 30
            font.weight: Font.DemiBold
            renderType: Text.NativeRendering
            font.hintingPreference: Font.PreferNoHinting
        }

        Text {
            width: parent.width
            visible: text !== ""
            text: root.a && root.a.body ? root.a.body : ""
            color: DrawerTheme.cream2
            wrapMode: Text.WordWrap
            lineHeight: 1.15
            font.family: Fonts.ui
            font.pixelSize: 18
            renderType: Text.NativeRendering
            font.hintingPreference: Font.PreferNoHinting
        }

        Text {
            width: parent.width
            visible: text !== ""
            text: root.a && root.a.hint ? root.a.hint : ""
            color: DrawerTheme.islandMuted
            wrapMode: Text.WordWrap
            font.family: Fonts.ui
            font.pixelSize: 15
            renderType: Text.NativeRendering
            font.hintingPreference: Font.PreferNoHinting
        }

        Item { width: 1; height: 4 }

        Row {
            visible: root.answered
            spacing: 10
            height: 44
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "\ue06c"
                color: DrawerTheme.cream
                font.family: Fonts.iconLucide
                font.pixelSize: 20
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                width: content.width - 40
                text: BoussoleState.ackText !== "" ? BoussoleState.ackText : "…"
                color: DrawerTheme.cream
                wrapMode: Text.WordWrap
                font.family: Fonts.ui
                font.pixelSize: 18
                font.weight: Font.Medium
                renderType: Text.NativeRendering
                font.hintingPreference: Font.PreferNoHinting
            }
        }

        Flow {
            visible: !root.answered
            width: parent.width
            spacing: 10
            Repeater {
                model: root.a ? root.a.actions : []
                delegate: Rectangle {
                    id: btn
                    required property var modelData
                    readonly property bool primary: modelData.primary === true
                    height: 44
                    width: label.implicitWidth + 36
                    radius: height / 2
                    color: btn.primary ? (hit.containsMouse ? DrawerTheme.cream2 : DrawerTheme.cream) : (hit.containsMouse ? DrawerTheme.islandCard : "transparent")
                    border.width: btn.primary ? 0 : 1
                    border.color: DrawerTheme.islandCardRaised
                    Text {
                        id: label
                        anchors.centerIn: parent
                        text: btn.modelData.label
                        color: btn.primary ? "#0c0c0e" : DrawerTheme.cream
                        font.family: Fonts.ui
                        font.pixelSize: 15
                        font.weight: Font.DemiBold
                        renderType: Text.NativeRendering
                        font.hintingPreference: Font.PreferNoHinting
                    }
                    MouseArea {
                        id: hit
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: BoussoleState.answer(btn.modelData.id)
                    }
                }
            }
        }
    }
}
