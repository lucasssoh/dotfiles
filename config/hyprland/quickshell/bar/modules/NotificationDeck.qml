import QtQuick
import Quickshell
import "../theme"
import "../services"

// What waits behind a full toast stack (NotificationState's maxToasts):
// the bottoms of the cards underneath, peeking out under the last one,
// and how many there are. Only a picture: parked toasts run out here, or
// come back up when one above is closed.
Item {
    id: root

    property int cardWidth: 340
    readonly property int count: NotificationState.parkedCount

    // The last count stays written while the deck fades out.
    property int shown: 0
    onCountChanged: if (root.count > 0) root.shown = root.count

    // Where shell.qml asks Hyprland to blur, relative to this item: each
    // card's whole lower part, its top tucked under the card above (whose
    // own blur covers that), so the rounded bottom corners come out right.
    readonly property rect frontBlur: Qt.rect(front.x, front.y - front.tuck, front.width, front.height + front.tuck)
    readonly property rect backBlur: Qt.rect(back.x, back.y - back.tuck, back.width, back.visible ? back.height + back.tuck : 0)

    width: root.cardWidth
    height: 32
    opacity: root.count > 0 ? 1 : 0
    visible: opacity > 0
    Behavior on opacity { NumberAnimation { duration: 200 } }

    // One card's bottom edge: a glass card clipped to the strip below the
    // card above, so its top edge never shows.
    component Edge: Item {
        id: edge
        property real tuck: 20
        property real alpha: 1
        clip: true
        anchors.horizontalCenter: parent.horizontalCenter

        Rectangle {
            y: -edge.tuck
            width: edge.width
            height: edge.height + edge.tuck
            radius: 16
            color: Qt.rgba(DrawerTheme.paneTop.r, DrawerTheme.paneTop.g, DrawerTheme.paneTop.b, DrawerTheme.paneTop.a * edge.alpha)
            PaneEdge {
                radius: 16
                highlight: false
                rimColor: Qt.rgba(DrawerTheme.paneRim.r, DrawerTheme.paneRim.g, DrawerTheme.paneRim.b, DrawerTheme.paneRim.a * edge.alpha)
            }
        }
    }

    Edge {
        id: back
        visible: root.shown > 1
        y: 7
        z: -1
        tuck: 27
        width: root.cardWidth - 44
        height: 6
        alpha: 0.55
    }

    Edge {
        id: front
        y: 0
        width: root.cardWidth - 20
        height: 7
        alpha: 0.9
    }

    // The parked toasts' app icons, overlapping, then their count.
    Row {
        anchors.horizontalCenter: parent.horizontalCenter
        y: 15
        spacing: 6

        Row {
            visible: iconRepeater.count > 0
            spacing: -6
            anchors.verticalCenter: parent.verticalCenter

            Repeater {
                id: iconRepeater
                model: NotificationState.parkedIcons.filter((icon) => icon !== "")
                delegate: Rectangle {
                    id: iconTile
                    required property string modelData
                    width: 18
                    height: 18
                    radius: 6
                    color: DrawerTheme.paneTop
                    border.width: 1.5
                    border.color: DrawerTheme.paneTop
                    Image {
                        anchors.centerIn: parent
                        width: 13
                        height: 13
                        fillMode: Image.PreserveAspectFit
                        sourceSize.width: 26
                        sourceSize.height: 26
                        source: {
                            const icon = iconTile.modelData;
                            if (icon.startsWith("/") || icon.includes("://")) return icon;
                            return Quickshell.iconPath(icon, true);
                        }
                    }
                }
            }
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            renderType: Text.NativeRendering
            font.hintingPreference: Font.PreferNoHinting
            text: "+" + root.shown
            color: DrawerTheme.secondary
            font.family: Fonts.ui
            font.pixelSize: 12
            font.weight: Font.Medium
        }
    }
}
