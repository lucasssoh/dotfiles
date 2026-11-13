import QtQuick
import Quickshell
import Quickshell.Services.Notifications
import "../theme"
import "../services"

// One toast in NotificationToast.qml's stack: a pane of the drawers'
// glass (Hyprland blurs behind it, see shell.qml), softer than the
// centre's cards. A 40px tile on the left (the notification's picture,
// else its app's icon), then the app's name, the summary and two lines of
// body; actions as a row of buttons across the bottom. The close button
// shows under the pointer only. The centre keeps NotificationCard.qml.
//
// Height is summed by hand, not read off a Column: a Column settles a
// frame late, and the list had by then placed the next card over this one.
Rectangle {
    id: card

    required property var notification
    signal dismissRequested()
    signal actionRequested(var action)

    readonly property bool critical: card.notification
        && card.notification.urgency === NotificationUrgency.Critical
    readonly property bool hasImage: card.notification && card.notification.image !== ""
    readonly property bool hasActions: card.notification && card.notification.actions.length > 0
    readonly property bool hasBody: card.notification && card.notification.body !== ""
    // notify-send names itself when the sender gives no app name: that is
    // the program, not something the person knows, so the line goes.
    readonly property string appName: {
        const name = card.notification ? card.notification.appName : "";
        return name === "notify-send" ? "" : name;
    }
    readonly property string appIconPath: {
        const icon = card.notification ? card.notification.appIcon : "";
        if (!icon) return "";
        if (icon.startsWith("/") || icon.includes("://")) return icon;
        return Quickshell.iconPath(icon, true);
    }
    // A critical one does not leave on its own: it shows it.
    readonly property color titleColor: card.critical ? DrawerTheme.warning : DrawerTheme.primary

    readonly property int pad: 14
    readonly property int tile: 40
    readonly property real textHeight: (card.appName !== "" ? 16 + 2 : 0)
        + summary.implicitHeight
        + (card.hasBody ? 2 + bodyText.implicitHeight : 0)
    readonly property real contentHeight: Math.max(card.tile, card.textHeight)

    width: 340
    radius: 26
    height: card.pad + card.contentHeight + (card.hasActions ? 12 + actionRow.height : card.pad)
    color: DrawerTheme.paneTop

    HoverHandler { id: hover }

    PaneEdge {
        radius: card.radius
        rimColor: card.critical
            ? Qt.rgba(DrawerTheme.warning.r, DrawerTheme.warning.g, DrawerTheme.warning.b, 0.7)
            : DrawerTheme.paneRim
    }

    Rectangle {
        id: tileRect
        x: card.pad
        y: card.pad
        width: card.tile
        height: card.tile
        radius: 13
        color: DrawerTheme.cardRaised
        clip: true

        Image {
            id: picture
            anchors.fill: parent
            visible: card.hasImage && status === Image.Ready
            fillMode: Image.PreserveAspectCrop
            source: card.hasImage ? card.notification.image : ""
            sourceSize.width: card.tile * 2
            sourceSize.height: card.tile * 2
        }
        Image {
            id: appIcon
            anchors.centerIn: parent
            width: 24
            height: 24
            visible: !picture.visible && card.appIconPath !== "" && status === Image.Ready
            fillMode: Image.PreserveAspectFit
            source: card.appIconPath
            sourceSize.width: 48
            sourceSize.height: 48
        }
        // Also when the picture is gone: a sender's temporary file
        // (satty's thumbnails) no longer exists once it has quit.
        Text {
            visible: !picture.visible && !appIcon.visible
            anchors.centerIn: parent
            renderType: Text.NativeRendering
            font.hintingPreference: Font.PreferNoHinting
            text: ""   // mgc notification
            color: card.critical ? DrawerTheme.warning : DrawerTheme.secondary
            font.family: Fonts.iconMingcute
            font.pixelSize: 18
        }
    }

    Column {
        id: textCol
        x: tileRect.x + card.tile + 12
        y: card.pad
        width: card.width - x - card.pad - 2
        spacing: 2

        Text {
            visible: card.appName !== ""
            width: parent.width - 22   // clear of the close button
            height: 16
            verticalAlignment: Text.AlignVCenter
            renderType: Text.NativeRendering
            font.hintingPreference: Font.PreferNoHinting
            text: card.appName
            color: DrawerTheme.muted
            font.family: Fonts.ui
            font.pixelSize: 12
            elide: Text.ElideRight
        }
        Text {
            id: summary
            width: parent.width - (card.appName !== "" ? 0 : 22)
            renderType: Text.NativeRendering
            font.hintingPreference: Font.PreferNoHinting
            text: card.notification ? card.notification.summary : ""
            color: card.titleColor
            font.family: Fonts.ui
            font.pixelSize: 14
            font.weight: Font.Medium
            elide: Text.ElideRight
        }
        Text {
            id: bodyText
            width: parent.width
            visible: card.hasBody
            renderType: Text.NativeRendering
            font.hintingPreference: Font.PreferNoHinting
            text: card.hasBody ? card.notification.body : ""
            color: DrawerTheme.ink(0.7)
            font.family: Fonts.ui
            font.pixelSize: 13
            wrapMode: Text.WordWrap
            maximumLineCount: 2
            elide: Text.ElideRight
        }
    }

    // Under the pointer only: a full stack used to wear three crosses.
    Item {
        id: closeBtn
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.rightMargin: 12
        anchors.topMargin: 11
        width: 20
        height: 20
        opacity: hover.hovered ? 1 : 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: 150 } }

        Rectangle {
            anchors.centerIn: parent
            width: 12
            height: 1.5
            radius: 1
            color: DrawerTheme.ink(0.5)
            rotation: 45
        }
        Rectangle {
            anchors.centerIn: parent
            width: 12
            height: 1.5
            radius: 1
            color: DrawerTheme.ink(0.5)
            rotation: -45
        }
        MouseArea {
            anchors.fill: parent
            anchors.margins: -4
            cursorShape: Qt.PointingHandCursor
            onClicked: card.dismissRequested()
        }
    }

    // Actions: one row of equal buttons across the bottom, under a
    // hairline, split by hairlines. The outer two round off with the card.
    Item {
        id: actionRow
        visible: card.hasActions
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: card.hasActions ? 40 : 0

        Rectangle {
            width: parent.width
            height: 1
            color: DrawerTheme.paneRim
        }

        Row {
            y: 1
            width: parent.width
            height: parent.height - 1

            Repeater {
                id: actionRepeater
                model: card.hasActions ? card.notification.actions : []
                delegate: Item {
                    id: actionCell
                    required property var modelData
                    required property int index
                    width: actionRow.width / actionRepeater.count
                    height: parent.height

                    Rectangle {
                        anchors.fill: parent
                        color: actionArea.containsMouse ? DrawerTheme.ink(0.06) : "transparent"
                        bottomLeftRadius: actionCell.index === 0 ? card.radius : 0
                        bottomRightRadius: actionCell.index === actionRepeater.count - 1 ? card.radius : 0
                        Behavior on color { ColorAnimation { duration: 120 } }
                    }
                    Rectangle {
                        visible: actionCell.index > 0
                        width: 1
                        height: parent.height
                        color: DrawerTheme.paneRim
                    }
                    Text {
                        anchors.centerIn: parent
                        width: parent.width - 16
                        horizontalAlignment: Text.AlignHCenter
                        renderType: Text.NativeRendering
                        font.hintingPreference: Font.PreferNoHinting
                        text: actionCell.modelData.text
                        color: DrawerTheme.primary
                        font.family: Fonts.ui
                        font.pixelSize: 13
                        font.weight: Font.Medium
                        elide: Text.ElideRight
                    }
                    MouseArea {
                        id: actionArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: card.actionRequested(actionCell.modelData)
                    }
                }
            }
        }
    }
}
