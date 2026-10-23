import QtQuick
import "../../theme"

// A one-line text field in the drawers' look, with a placeholder.
// `accepted` on Enter.
Rectangle {
    id: field

    property alias text: input.text
    property string placeholder: ""
    signal accepted()

    width: parent ? parent.width : 200
    height: 40
    radius: 12
    color: DrawerTheme.card
    border.width: input.activeFocus ? 1 : 0
    border.color: DrawerTheme.secondary

    TextInput {
        id: input
        anchors.fill: parent
        anchors.leftMargin: 12
        anchors.rightMargin: 12
        verticalAlignment: TextInput.AlignVCenter
        color: DrawerTheme.primary
        font.family: Fonts.ui
        font.pixelSize: 14
        clip: true
        selectByMouse: true
        onAccepted: field.accepted()
    }
    Text {
        anchors.verticalCenter: parent.verticalCenter
        x: 12
        visible: input.text === "" && !input.activeFocus
        text: field.placeholder
        color: DrawerTheme.muted
        font.family: Fonts.ui
        font.pixelSize: 14
        renderType: Text.NativeRendering
    }
    MouseArea {
        anchors.fill: parent
        visible: !input.activeFocus
        cursorShape: Qt.IBeamCursor
        onClicked: input.forceActiveFocus()
    }
}
