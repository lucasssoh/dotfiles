import QtQuick
import "../theme"
import "../services"

// What waits behind a full toast stack (NotificationState's maxToasts):
// the bottoms of the cards underneath and how many there are. Only a
// picture -- parked toasts come back into the stack as places free up.
Item {
    id: root

    property int cardWidth: 340
    readonly property int count: NotificationState.parkedCount
    // shell.qml asks Hyprland to blur behind both strips.
    readonly property alias front: front
    readonly property alias back: back

    // The last count stays written while the deck fades out.
    property int shown: 0
    onCountChanged: if (root.count > 0) root.shown = root.count

    width: root.cardWidth
    height: 18
    opacity: root.count > 0 ? 1 : 0
    visible: opacity > 0
    Behavior on opacity { NumberAnimation { duration: 200 } }

    Rectangle {
        id: back
        visible: root.shown > 1
        anchors.horizontalCenter: parent.horizontalCenter
        y: 7
        width: root.cardWidth - 48
        height: 7
        radius: 7
        topLeftRadius: 0
        topRightRadius: 0
        color: Qt.rgba(DrawerTheme.paneTop.r, DrawerTheme.paneTop.g, DrawerTheme.paneTop.b, DrawerTheme.paneTop.a * 0.6)
        opacity: 0.7

        PaneEdge {
            radius: 7
            topLeftRadius: 0
            topRightRadius: 0
            highlight: false
        }
    }

    Rectangle {
        id: front
        anchors.horizontalCenter: parent.horizontalCenter
        width: root.cardWidth - 24
        height: 7
        radius: 7
        topLeftRadius: 0
        topRightRadius: 0
        color: DrawerTheme.paneTop

        PaneEdge {
            radius: 7
            topLeftRadius: 0
            topRightRadius: 0
            highlight: false
        }
    }

    Rectangle {
        anchors.right: front.right
        anchors.rightMargin: 10
        y: 2
        width: countText.implicitWidth + 12
        height: 16
        radius: 8
        color: DrawerTheme.paneTop

        Text {
            id: countText
            anchors.centerIn: parent
            text: "+" + root.shown
            color: DrawerTheme.secondary
            font.family: Fonts.ui
            font.pixelSize: 11
            font.weight: Font.Medium
            font.hintingPreference: Font.PreferNoHinting
        }
    }
}
