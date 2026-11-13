import QtQuick
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Services.Notifications
import "../theme"
import "../services"

// One notification's line in a NotificationCenter.qml app card: no fill
// of its own (the app's card is under it), no app name (the card's header
// has it), its arrival time at the end of the summary. Same language as
// the toasts (NotificationToastCard.qml): the close button shows under
// the pointer, in the time's place; the line lightens a touch there; a
// wide picture shows in full under the text; actions are a row of
// buttons along its bottom; a critical one's title is amber.
//
// `continued`: the line right above is from the same sender (same
// summary), so the summary is not repeated -- the body takes its row,
// time beside it. Every notification still keeps its own line.
//
// Pure rendering + two request signals; NotificationState.qml decides
// what dismiss/action do. Every animation runs once, on an event.
//
// Height is summed by hand, not read off a Column: a Column settles a
// frame late, and the card would lay out against a stale height.
Item {
    id: card

    required property var notification
    signal dismissRequested()
    signal actionRequested(var action)

    // The picture the card's header already shows: not repeated here.
    property string groupImage: ""
    property string timeText: ""
    property bool continued: false
    // The card's last line: its hover fill and actions round off with it.
    property bool last: false
    // Arrived while the drawer is open: comes in like a toast.
    property bool arriving: false

    readonly property bool critical: card.notification
        && card.notification.urgency === NotificationUrgency.Critical
    readonly property bool hasImage: card.notification && card.notification.image !== ""
    readonly property bool hasActions: card.notification && card.notification.actions.length > 0
    readonly property bool hasBody: card.notification && card.notification.body !== ""

    // A picture sent as a file path reaches us as "image://icon//<path>",
    // which the icon provider hands back at icon size: load the file.
    readonly property string imageSource: {
        const image = card.hasImage ? card.notification.image : "";
        return image.startsWith("image://icon//") ? "file://" + image.slice("image://icon/".length) : image;
    }
    // satty sends a 96x60 thumbnail, in a temporary file gone once it
    // quits, and names the saved file in its body: "File saved to
    // '<path>'". When a notification's picture is a file and its body
    // quotes an absolute path, that file is the picture -- full size, and
    // still there later. Back to the sent picture if it will not load.
    readonly property string savedPath: {
        if (!card.imageSource.startsWith("file://") || !card.hasBody) return "";
        const m = card.notification.body.match(/'(\/[^']+)'/);
        return m ? m[1] : "";
    }
    property bool savedFailed: false
    readonly property string pictureSource: card.savedPath !== "" && !card.savedFailed
        ? "file://" + card.savedPath : card.imageSource
    readonly property bool imageIsIcon: card.imageSource.startsWith("image://icon/")
    // A wide picture (a screenshot) shows under the text; a square one (a
    // contact's photo) in the tile, unless the header already shows it.
    readonly property real pictureRatio: probe.status === Image.Ready && probe.implicitHeight > 0
        ? probe.implicitWidth / probe.implicitHeight : 0
    readonly property bool widePicture: card.hasImage && !card.imageIsIcon
        && probe.implicitWidth >= 240 && card.pictureRatio >= 1.2
    readonly property bool showIcon: card.hasImage && !card.widePicture && !card.continued
        && card.notification.image !== card.groupImage
    readonly property real thumbHeight: card.widePicture
        ? Math.min(170, Math.round(textCol.width / card.pictureRatio)) : 0

    readonly property int topPad: card.continued ? 2 : 10
    readonly property real textHeight: (card.continued
            ? (card.hasBody ? bodyText.implicitHeight : summary.implicitHeight)
            : summary.implicitHeight + (card.hasBody ? 2 + bodyText.implicitHeight : 0))
        + (card.widePicture ? 8 + card.thumbHeight : 0)
    readonly property real contentHeight: Math.max(card.showIcon ? 28 : 0, card.textHeight)

    width: 340
    height: card.topPad + card.contentHeight + (card.hasActions ? 10 + actionRow.height : 10)

    HoverHandler { id: hover }

    // Under the pointer the line lightens a touch, as a toast does.
    Rectangle {
        anchors.fill: parent
        color: DrawerTheme.ink(0.05)
        opacity: hover.hovered ? 1 : 0
        bottomLeftRadius: card.last ? 16 : 0
        bottomRightRadius: card.last ? 16 : 0
        Behavior on opacity { NumberAnimation { duration: 150 } }
    }

    Item {
        id: content
        width: parent.width
        height: parent.height
        transform: Translate { id: contentShift }

        Rectangle {
            id: iconTile
            visible: card.showIcon
            x: 14
            y: card.topPad
            width: 28
            height: 28
            radius: 8
            color: DrawerTheme.cardRaised
            clip: true

            Image {
                id: iconImage
                anchors.fill: parent
                anchors.margins: card.imageIsIcon ? 2 : 0
                visible: status === Image.Ready
                fillMode: Image.PreserveAspectCrop
                source: card.showIcon ? card.imageSource : ""
                sourceSize.width: 56
                sourceSize.height: 56
            }
            // Also when the image is gone: a sender's temporary file
            // (satty's thumbnails) no longer exists once it has quit.
            Text {
                visible: !iconImage.visible
                anchors.centerIn: parent
                renderType: Text.NativeRendering
                font.hintingPreference: Font.PreferNoHinting
                text: ""   // mgc notification
                color: card.critical ? DrawerTheme.warning : DrawerTheme.secondary
                font.family: Fonts.iconMingcute
                font.pixelSize: 14
            }
        }

        // Only measures the picture: decoded once, its implicit size is
        // what tells a screenshot from a photo.
        Image {
            id: probe
            visible: false
            asynchronous: true
            source: card.hasImage && !card.imageIsIcon ? card.pictureSource : ""
            sourceSize.width: 640
            onStatusChanged: if (status === Image.Error && card.savedPath !== "") card.savedFailed = true
        }

        Column {
            id: textCol
            x: card.showIcon ? iconTile.x + iconTile.width + 10 : 14
            y: card.topPad
            width: card.width - x - 10 - 20 - 8   // clear of the time / close slot
            spacing: 2
            transform: Translate { id: textShift }

            Text {
                id: summary
                visible: !card.continued || !card.hasBody
                width: parent.width
                renderType: Text.NativeRendering
                font.hintingPreference: Font.PreferNoHinting
                text: card.notification ? card.notification.summary : ""
                color: card.critical ? DrawerTheme.warning : DrawerTheme.primary
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
                height: card.widePicture ? 6 + card.thumbHeight : 0

                // Rounded by a mask: a layer drawn once and cached.
                Image {
                    id: thumb
                    y: 6
                    width: parent.width
                    height: card.thumbHeight
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    source: card.widePicture ? card.pictureSource : ""
                    sourceSize.width: 640
                    layer.enabled: card.widePicture
                    layer.effect: OpacityMask {
                        maskSource: Rectangle {
                            width: thumb.width
                            height: thumb.height
                            radius: 12
                        }
                    }
                }
                Rectangle {
                    y: 6
                    width: parent.width
                    height: card.thumbHeight
                    radius: 12
                    color: "transparent"
                    border.width: 1
                    border.color: DrawerTheme.ink(DrawerTheme.dark ? 0.07 : 0.08)
                }
            }
        }

        // The time, and in its place under the pointer the close button.
        Text {
            id: timeLabel
            visible: card.timeText !== "" && opacity > 0
            anchors.right: parent.right
            anchors.rightMargin: 10
            // On the first text line's baseline. By hand: that line lives
            // in textCol, and anchors only reach siblings.
            readonly property Item firstLine: card.continued && card.hasBody ? bodyText : summary
            y: textCol.y + firstLine.y + firstLine.baselineOffset - timeLabel.baselineOffset
            renderType: Text.NativeRendering
            font.hintingPreference: Font.PreferNoHinting
            text: card.timeText
            color: DrawerTheme.secondary
            font.family: Fonts.ui
            font.pixelSize: 12
            font.features: { "tnum": 1 }
            opacity: hover.hovered ? 0 : 1
            Behavior on opacity { NumberAnimation { duration: 150 } }
        }
        Item {
            id: closeBtn
            anchors.right: parent.right
            anchors.rightMargin: 10
            y: card.topPad + (card.continued && card.hasBody ? bodyText.y : summary.y)
                + ((card.continued && card.hasBody ? 18 : summary.implicitHeight) - height) / 2
            width: 20
            height: 20
            opacity: hover.hovered ? 1 : 0
            visible: opacity > 0
            Behavior on opacity { NumberAnimation { duration: 150 } }

            Rectangle { anchors.centerIn: parent; width: 12; height: 1.5; radius: 1; color: DrawerTheme.ink(0.5); rotation: 45 }
            Rectangle { anchors.centerIn: parent; width: 12; height: 1.5; radius: 1; color: DrawerTheme.ink(0.5); rotation: -45 }
            MouseArea {
                anchors.fill: parent
                anchors.margins: -4
                cursorShape: Qt.PointingHandCursor
                onClicked: card.dismissRequested()
            }
        }

        // Actions: one row of equal buttons across the line, under a
        // hairline, split by hairlines. A pressed one stays dark once
        // chosen, while the notification leaves.
        Item {
            id: actionRow
            visible: card.hasActions
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: card.hasActions ? 38 : 0

            Rectangle {
                x: 14
                width: parent.width - 28
                height: 1
                color: DrawerTheme.ink(DrawerTheme.dark ? 0.07 : 0.08)
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
                            bottomLeftRadius: card.last && actionCell.index === 0 ? 16 : 0
                            bottomRightRadius: card.last && actionCell.index === actionRepeater.count - 1 ? 16 : 0
                            Behavior on color { ColorAnimation { duration: 90 } }
                        }
                        Rectangle {
                            visible: actionCell.index > 0
                            y: 8
                            width: 1
                            height: parent.height - 16
                            color: DrawerTheme.ink(DrawerTheme.dark ? 0.07 : 0.08)
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
    property int chosenAction: -1

    // Arriving while the drawer is open, in two beats like a toast: the
    // line slides in 16px from the right as it fades in, its text follows
    // 60ms later, rising 4px.
    SequentialAnimation {
        id: arrive
        PropertyAction { target: content; property: "opacity"; value: 0 }
        PropertyAction { target: contentShift; property: "x"; value: 16 }
        PropertyAction { target: textCol; property: "opacity"; value: 0 }
        PropertyAction { target: textShift; property: "y"; value: 4 }
        ParallelAnimation {
            NumberAnimation { target: content; property: "opacity"; to: 1; duration: 240; easing.type: Easing.OutQuint }
            NumberAnimation { target: contentShift; property: "x"; to: 0; duration: 240; easing.type: Easing.OutQuint }
            SequentialAnimation {
                PauseAnimation { duration: 60 }
                ParallelAnimation {
                    NumberAnimation { target: textCol; property: "opacity"; to: 1; duration: 220; easing.type: Easing.OutQuint }
                    NumberAnimation { target: textShift; property: "y"; to: 0; duration: 220; easing.type: Easing.OutQuint }
                }
            }
        }
    }
    Component.onCompleted: if (card.arriving) arrive.start()
}
