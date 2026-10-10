import QtQuick
import "../../theme"
import "../../services"

// The password card, centred on a veil over the whole screen: what asks,
// the command that asked for it, the field. Enter answers, Escape cancels.
// Built while an ask is open and destroyed once it has faded (shell.qml).
Item {
    id: root

    readonly property var ask: SesameState.card
    readonly property bool open: SesameState.open
    readonly property bool confirm: root.ask ? root.ask.confirm : false
    readonly property var chain: root.ask ? (root.ask.chain || []) : []

    readonly property string glyph: {
        const k = root.ask ? root.ask.kind : "";
        return k === "polkit" ? "" : k === "gpg" ? "" : "";
    }
    readonly property string okLabel: {
        if (!root.ask) return "OK";
        if (root.confirm) return "Allow";
        if (root.ask.kind === "polkit") return "Authenticate";
        if (root.ask.echo) return "Send";
        return "Unlock";
    }

    function submit() {
        if (!root.open) return;
        const s = root.confirm ? "" : field.text;
        field.text = "";
        SesameState.answer(s);
    }
    function dismiss() {
        if (!root.open) return;
        field.text = "";
        SesameState.cancel();
    }

    // A new ask (a retry, the next in the queue): empty field, focus back.
    property var lastId: null
    onAskChanged: {
        if (root.ask && root.ask.id !== root.lastId) {
            root.lastId = root.ask.id;
            field.text = "";
            Qt.callLater(root.focusInput);
        }
    }
    Component.onCompleted: root.focusInput()
    function focusInput() {
        if (root.confirm) keyCatcher.forceActiveFocus();
        else field.forceActiveFocus();
    }

    Rectangle {
        anchors.fill: parent
        color: "black"
        opacity: root.open ? 0.38 : 0
        Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
    }
    // The veil takes the clicks: nothing behind is reachable while asked.
    MouseArea {
        anchors.fill: parent
        onClicked: root.focusInput()
    }

    Keys.onEscapePressed: root.dismiss()

    Rectangle {
        id: card
        anchors.centerIn: parent
        width: 440
        height: column.height + 24 * 2
        radius: 30
        color: DrawerTheme.panelTop
        border.width: 1
        border.color: DrawerTheme.ink(0.08)

        opacity: root.open ? 1 : 0
        scale: root.open ? 1 : 0.96
        Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
        Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

        // Clicks on the card stay on the card.
        MouseArea { anchors.fill: parent; onClicked: root.focusInput() }

        Column {
            id: column
            x: 24
            y: 24
            width: card.width - 48
            spacing: 16

            Row {
                width: parent.width
                spacing: 12

                Rectangle {
                    width: 42
                    height: 42
                    radius: 14
                    color: DrawerTheme.card
                    Text {
                        anchors.centerIn: parent
                        text: root.glyph
                        color: DrawerTheme.primary
                        font.family: Fonts.iconLucide
                        font.pixelSize: 20
                    }
                }
                Column {
                    width: parent.width - 54
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 3
                    Text {
                        width: parent.width
                        renderType: Text.NativeRendering
                        text: root.ask ? root.ask.title : ""
                        color: DrawerTheme.primary
                        font.family: Fonts.ui
                        font.pixelSize: 15
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                    }
                    Text {
                        width: parent.width
                        renderType: Text.NativeRendering
                        text: root.ask ? root.ask.message : ""
                        color: DrawerTheme.secondary
                        font.family: Fonts.ui
                        font.pixelSize: 12
                        wrapMode: Text.Wrap
                        maximumLineCount: 6
                        elide: Text.ElideRight
                    }
                }
            }

            // Asked by: outermost first, the step that asks last and brightest.
            Column {
                visible: root.chain.length > 0
                width: parent.width
                spacing: 6

                Text {
                    renderType: Text.NativeRendering
                    text: "Asked by"
                    color: DrawerTheme.secondary
                    font.family: Fonts.ui
                    font.pixelSize: 11
                    font.letterSpacing: 0.4
                }
                Rectangle {
                    width: parent.width
                    height: steps.height + 12 * 2
                    radius: 14
                    color: DrawerTheme.card

                    Column {
                        id: steps
                        x: 14
                        y: 12
                        width: parent.width - 28
                        spacing: 3
                        Repeater {
                            model: root.chain
                            Text {
                                required property string modelData
                                required property int index
                                readonly property bool last: index === root.chain.length - 1
                                width: steps.width
                                renderType: Text.NativeRendering
                                text: (index > 0 ? "› " : "") + modelData
                                color: last ? DrawerTheme.primary : DrawerTheme.secondary
                                font.family: Fonts.mono
                                font.pixelSize: 12
                                leftPadding: Math.min(index, 3) * 10
                                elide: Text.ElideRight
                            }
                        }
                    }
                }
            }

            Text {
                visible: root.ask && root.ask.error !== ""
                width: parent.width
                renderType: Text.NativeRendering
                text: root.ask ? root.ask.error : ""
                color: DrawerTheme.danger
                font.family: Fonts.ui
                font.pixelSize: 12
                wrapMode: Text.Wrap
            }

            // Outlined, not filled: the shell keeps away from white slabs.
            Rectangle {
                visible: !root.confirm
                width: parent.width
                height: 42
                radius: 13
                color: "transparent"
                border.width: field.activeFocus ? 1.5 : 1
                border.color: field.activeFocus ? DrawerTheme.primary : DrawerTheme.faint

                TextInput {
                    id: field
                    anchors.fill: parent
                    anchors.leftMargin: 14
                    anchors.rightMargin: 14
                    verticalAlignment: TextInput.AlignVCenter
                    echoMode: root.ask && root.ask.echo ? TextInput.Normal : TextInput.Password
                    passwordCharacter: "•"
                    color: DrawerTheme.primary
                    selectionColor: DrawerTheme.ink(0.25)
                    font.family: Fonts.ui
                    font.pixelSize: 14
                    clip: true
                    focus: true
                    Keys.onReturnPressed: root.submit()
                    Keys.onEnterPressed: root.submit()
                    Keys.onEscapePressed: root.dismiss()

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: field.text.length === 0
                        renderType: Text.NativeRendering
                        text: !root.ask ? "" : root.ask.echo ? "Answer" : root.ask.kind === "polkit" || root.ask.kind === "git" ? "Password" : "Passphrase"
                        color: DrawerTheme.muted
                        font.family: Fonts.ui
                        font.pixelSize: 14
                    }
                }
            }

            Row {
                anchors.right: parent.right
                spacing: 8

                Repeater {
                    model: [
                        { label: root.confirm ? "Deny" : "Cancel", main: false },
                        { label: root.okLabel, main: true }
                    ]
                    Rectangle {
                        required property var modelData
                        width: label.implicitWidth + 36
                        height: 36
                        radius: 18
                        color: modelData.main
                            ? (hover.containsMouse ? Qt.darker(DrawerTheme.on, DrawerTheme.dark ? 1.08 : 0.8) : DrawerTheme.on)
                            : (hover.containsMouse ? DrawerTheme.cardHover : DrawerTheme.card)
                        Text {
                            id: label
                            anchors.centerIn: parent
                            renderType: Text.NativeRendering
                            text: modelData.label
                            color: modelData.main ? DrawerTheme.onInk : DrawerTheme.primary
                            font.family: Fonts.ui
                            font.pixelSize: 13
                            font.weight: Font.DemiBold
                        }
                        MouseArea {
                            id: hover
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: modelData.main ? root.submit() : root.dismiss()
                        }
                    }
                }
            }
        }
    }

    // Allow/Deny cards have no field to hold the keys.
    Item {
        id: keyCatcher
        Keys.onReturnPressed: root.submit()
        Keys.onEnterPressed: root.submit()
        Keys.onEscapePressed: root.dismiss()
    }
}
