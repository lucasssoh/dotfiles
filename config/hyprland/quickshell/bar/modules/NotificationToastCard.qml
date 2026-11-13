import QtQuick
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Services.Notifications
import "../theme"
import "../services"

// One toast in NotificationToast.qml's stack: a pane of the drawers'
// glass (Hyprland blurs behind it, see shell.qml), softer than the
// centre's cards. A 40px tile on the left (the notification's picture,
// else its app's icon), then the app's name, the summary and two lines of
// body; a wide picture (a screenshot) shows in full under the text;
// actions as a row of buttons across the bottom. The close button shows
// under the pointer only. The centre keeps NotificationCard.qml.
//
// Every animation here runs once, on an event (arrival, hover, a click,
// an update): nothing loops, so a toast sitting on screen draws nothing.
//
// Height is summed by hand, not read off a Column: a Column settles a
// frame late, and the list had by then placed the next card over this one.
Rectangle {
    id: card

    required property var notification
    // Messages merged into this toast (NotificationState's grouping).
    property int count: 1
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
    // A picture sent as a file path reaches us as "image://icon//<path>",
    // and the icon provider hands it back at icon size (2x1 here), losing
    // its real shape: load the file itself instead.
    readonly property string imageSource: {
        const image = card.hasImage ? card.notification.image : "";
        return image.startsWith("image://icon//") ? "file://" + image.slice("image://icon/".length) : image;
    }
    // An icon named as the picture (notify-send -i lands there): drawn at
    // icon size, never taken for a screenshot.
    readonly property bool imageIsIcon: card.imageSource.startsWith("image://icon/")
    // A critical one does not leave on its own: it shows it.
    readonly property color titleColor: card.critical ? DrawerTheme.warning : DrawerTheme.primary

    // A wide picture (a screenshot, not a contact's square photo) is shown
    // under the text instead of squeezed into the tile.
    readonly property real pictureRatio: picture.status === Image.Ready && picture.implicitHeight > 0
        ? picture.implicitWidth / picture.implicitHeight : 0
    readonly property bool widePicture: card.hasImage && !card.imageIsIcon && picture.implicitWidth >= 240 && card.pictureRatio >= 1.2
    readonly property real thumbHeight: card.widePicture
        ? Math.min(180, Math.round(textCol.width / card.pictureRatio)) : 0

    readonly property int pad: 14
    readonly property int tile: 40
    readonly property real textHeight: (card.appName !== "" ? 16 + 2 : 0)
        + summary.implicitHeight
        + (card.hasBody ? 2 + bodyText.implicitHeight : 0)
        + (card.widePicture ? 10 + card.thumbHeight : 0)
    readonly property real contentHeight: Math.max(card.tile, card.textHeight)

    width: 340
    radius: 26
    height: card.pad + card.contentHeight + (card.hasActions ? 12 + actionRow.height : card.pad)
    color: DrawerTheme.paneTop

    HoverHandler { id: hover }

    // Under the pointer the glass lightens a touch and its edge firms up,
    // along with the close button appearing: the card answers the pointer.
    Rectangle {
        anchors.fill: parent
        radius: card.radius
        color: DrawerTheme.ink(0.05)
        opacity: hover.hovered ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 150 } }
    }

    PaneEdge {
        radius: card.radius
        rimColor: card.critical
            ? Qt.rgba(DrawerTheme.warning.r, DrawerTheme.warning.g, DrawerTheme.warning.b, card.flare > 0 ? 0.7 + 0.3 * card.flare : 0.7)
            : Qt.rgba(DrawerTheme.paneRim.r, DrawerTheme.paneRim.g, DrawerTheme.paneRim.b,
                      Math.min(1, DrawerTheme.paneRim.a * (1 + 0.7 * hoverRim.value)))
    }
    QtObject {
        id: hoverRim
        property real value: hover.hovered ? 1 : 0
        Behavior on value { NumberAnimation { duration: 150 } }
    }

    // A critical toast flares once as it arrives: its edge brightens and
    // a ring spreads out from it and fades. Never more than once.
    property real flare: 0
    Rectangle {
        visible: card.critical && flareAnim.running
        anchors.fill: parent
        anchors.margins: -card.flareSpread
        radius: card.radius + card.flareSpread
        color: "transparent"
        border.width: 2
        border.color: Qt.rgba(DrawerTheme.warning.r, DrawerTheme.warning.g, DrawerTheme.warning.b, 0.35 * card.flare)
    }
    property real flareSpread: 1
    SequentialAnimation {
        id: flareAnim
        PauseAnimation { duration: 200 }
        ParallelAnimation {
            SequentialAnimation {
                NumberAnimation { target: card; property: "flare"; from: 0; to: 1; duration: 260; easing.type: Easing.OutQuad }
                NumberAnimation { target: card; property: "flare"; to: 0; duration: 640; easing.type: Easing.InOutQuad }
            }
            NumberAnimation { target: card; property: "flareSpread"; from: 1; to: 8; duration: 900; easing.type: Easing.OutCubic }
        }
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
            visible: card.hasImage && !card.widePicture && status === Image.Ready
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            source: card.imageSource
            // A picture is decoded once, at the width the wide picture
            // needs; its implicit size is what tells a screenshot from a
            // photo. An icon is asked for at the tile's size.
            sourceSize.width: card.imageIsIcon ? card.tile * 2 : 640
            sourceSize.height: card.imageIsIcon ? card.tile * 2 : 0
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
        transform: Translate { id: textShift }

        Text {
            visible: card.appName !== ""
            width: parent.width - 22   // clear of the close button
            height: 16
            verticalAlignment: Text.AlignVCenter
            renderType: Text.NativeRendering
            font.hintingPreference: Font.PreferNoHinting
            text: card.count > 1 ? card.appName + " · " + card.count : card.appName
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
        Item {
            visible: card.widePicture
            width: parent.width
            height: card.widePicture ? 10 + card.thumbHeight : 0

            // Rounded by a mask: a layer drawn once and cached, so it
            // costs nothing while the card sits or slides.
            Image {
                id: thumb
                y: 10
                width: parent.width
                height: card.thumbHeight
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                source: card.widePicture ? card.imageSource : ""
                sourceSize.width: 640
                layer.enabled: card.widePicture
                layer.effect: OpacityMask {
                    maskSource: Rectangle {
                        width: thumb.width
                        height: thumb.height
                        radius: 14
                    }
                }
            }
            Rectangle {
                y: 10
                width: parent.width
                height: card.thumbHeight
                radius: 14
                color: "transparent"
                border.width: 1
                border.color: DrawerTheme.paneRim
            }
        }
    }

    // Arriving in two beats: the card slides in (NotificationToast's add
    // transition), its text follows 60ms later, rising 4px as it fades in.
    // An update to its text (an app replacing its notification, or a
    // message merged into it) runs the same, shorter.
    SequentialAnimation {
        id: textIn
        property int delay: 60
        property int duration: 220
        PropertyAction { target: textCol; property: "opacity"; value: 0 }
        PropertyAction { target: textShift; property: "y"; value: 4 }
        PauseAnimation { duration: textIn.delay }
        ParallelAnimation {
            NumberAnimation { target: textCol; property: "opacity"; to: 1; duration: textIn.duration; easing.type: Easing.OutQuint }
            NumberAnimation { target: textShift; property: "y"; to: 0; duration: textIn.duration; easing.type: Easing.OutQuint }
        }
    }
    function swapText() {
        if (!card.ready) return;
        textIn.delay = 0;
        textIn.duration = 160;
        textIn.restart();
    }
    property bool ready: false
    Component.onCompleted: {
        textIn.start();
        if (card.critical) flareAnim.start();
        card.ready = true;
    }
    onNotificationChanged: card.swapText()
    Connections {
        target: card.notification
        function onSummaryChanged() { card.swapText(); }
        function onBodyChanged() { card.swapText(); }
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
    // A button darkens while pressed and stays dark once chosen, as the
    // card fades: the click visibly landed.
    property int chosenAction: -1
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
                        color: actionArea.pressed || card.chosenAction === actionCell.index
                            ? DrawerTheme.ink(0.12)
                            : (actionArea.containsMouse ? DrawerTheme.ink(0.06) : DrawerTheme.ink(0))
                        bottomLeftRadius: actionCell.index === 0 ? card.radius : 0
                        bottomRightRadius: actionCell.index === actionRepeater.count - 1 ? card.radius : 0
                        Behavior on color { ColorAnimation { duration: 90 } }
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
                        onClicked: {
                            card.chosenAction = actionCell.index;
                            card.actionRequested(actionCell.modelData);
                        }
                    }
                }
            }
        }
    }
}
