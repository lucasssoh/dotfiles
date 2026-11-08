import QtQuick
import Quickshell
import Quickshell.Services.Notifications
import "../theme"
import "../services"

// One rendered notification -- shared between NotificationToast.qml (the
// transient corner popup stack) and NotificationCenter.qml (the history
// list), since both show the exact same content (icon/image, summary,
// body, actions, a close button), just inside different containers.
// Pure rendering + two request signals; NotificationState.qml decides
// what dismiss/action actually do (toast-only hide vs. real dismiss()).
//
// In the centre the card is a flat veil of the ink over the drawer's
// glass; in a toast it is a pane of that glass itself (see `toast`).
// Height is content-driven: `layout` below has no bottom anchor, so its
// implicit height drives `card.height` with no feedback loop.
Rectangle {
    id: card

    required property var notification
    signal dismissRequested()
    signal actionRequested(var action)

    readonly property bool critical: card.notification
        && card.notification.urgency === NotificationUrgency.Critical
    readonly property color accent: card.critical ? DrawerTheme.danger : DrawerTheme.accent
    readonly property bool hasImage: card.notification && card.notification.image !== ""
    readonly property bool hasActions: card.notification && card.notification.actions.length > 0
    readonly property bool hasBody: card.notification && card.notification.body !== ""

    width: 340
    radius: card.row ? 0 : 20
    height: card.contentHeight + (card.row ? 20 : (card.toast ? 24 : 28))
    // Summed here rather than read off `layout`: a Column settles its
    // height a frame late, and the toast list had by then placed the next
    // card where this one ends up, overlapping it.
    readonly property real textHeight: summary.implicitHeight + (card.hasBody ? 2 + bodyText.implicitHeight : 0)
    readonly property real contentHeight: (card.toast ? 20 + 8 : 0)
        + Math.max(card.showIcon ? 28 : 0, card.textHeight, card.toast ? 0 : 20)
        + (card.hasActions ? 8 + 28 : 0)

    // Toast mode: the drawers' glass (B1), where it used to be pure black.
    // Same content as in the centre, read in one glance: app, summary,
    // body, actions.
    property bool toast: false

    // A line in the notification centre's app card: no fill of its own
    // (the app's card is under it), no app name or icon (its header has
    // them), and the arrival time at the end of the summary. An image of
    // its own, a contact's photo say, still shows: `groupImage` is the one
    // the header already shows.
    property bool row: false
    property string groupImage: ""
    property string timeText: ""
    readonly property bool showIcon: card.toast ? card.hasImage
        : (!card.row || (card.hasImage && card.notification.image !== card.groupImage))

    // A toast is a pane of the drawers' glass (B1): their veil, with
    // Hyprland's blur under it (shell.qml asks for it over each toast) and
    // their edge on top. It names its app on a first line, as the centre's
    // cards do; its picture, if it has one, stays beside the text.
    readonly property string appIconPath: {
        const icon = card.notification ? card.notification.appIcon : "";
        if (!icon) return "";
        if (icon.startsWith("/") || icon.includes("://")) return icon;
        return Quickshell.iconPath(icon, true);
    }

    color: card.row ? "transparent" : (card.toast ? DrawerTheme.paneTop : DrawerTheme.card)

    PaneEdge {
        visible: card.toast
        radius: card.radius
    }

    // In the centre the card carries no edge: it shows text, it is not a
    // button. The action pills and the close button are what you press.


    Column {
        id: layout
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.leftMargin: 14
        anchors.rightMargin: card.row || card.toast ? 10 : 14
        anchors.topMargin: card.row ? 10 : (card.toast ? 11 : 14)
        spacing: 8

        Item {
            visible: card.toast
            width: layout.width
            height: 20

            Rectangle {
                id: metaIcon
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                width: 16
                height: 16
                radius: 5
                color: DrawerTheme.cardRaised
                Image {
                    id: metaImage
                    anchors.fill: parent
                    visible: card.appIconPath !== "" && status !== Image.Error
                    fillMode: Image.PreserveAspectFit
                    source: card.appIconPath
                }
                Text {
                    visible: !metaImage.visible
                    anchors.centerIn: parent
                    renderType: Text.NativeRendering
                    font.hintingPreference: Font.PreferNoHinting
                    text: "\uF126"   // mgc notification
                    color: card.accent
                    font.family: Fonts.iconMingcute
                    font.pixelSize: 10
                }
            }
            Text {
                anchors.left: metaIcon.right
                anchors.leftMargin: 6
                anchors.right: metaClose.left
                anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                renderType: Text.NativeRendering
                font.hintingPreference: Font.PreferNoHinting
                text: card.notification ? (card.notification.appName || "Notifications") : ""
                color: DrawerTheme.secondary
                font.family: Fonts.ui
                font.pixelSize: 12
                font.weight: Font.Medium
                elide: Text.ElideRight
            }
            CloseCross {
                id: metaClose
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
            }
        }

        Item {
            id: headerRow
            width: layout.width
            height: Math.max(card.showIcon ? iconTile.height : 0, textCol.height, card.toast ? 0 : closeBtn.height)

            Rectangle {
                id: iconTile
                visible: card.showIcon
                anchors.left: parent.left
                anchors.top: parent.top
                width: 28
                height: 28
                radius: 8
                color: DrawerTheme.cardRaised

                Image {
                    id: iconImage
                    anchors.fill: parent
                    anchors.margins: 2
                    visible: card.hasImage && status !== Image.Error
                    fillMode: Image.PreserveAspectCrop
                    source: card.hasImage ? card.notification.image : ""
                }
                // Also when the image is gone: a sender's temporary file
                // (satty's thumbnails) no longer exists once it has quit.
                Text {
                    visible: !iconImage.visible
                    anchors.centerIn: parent
                    renderType: Text.NativeRendering
                    font.hintingPreference: Font.PreferNoHinting
                    text: "\uF126"   // mgc notification -- generic fallback when no image/icon
                    color: card.accent
                    font.family: Fonts.iconMingcute
                    font.pixelSize: 14
                }
            }

            CloseCross {
                id: closeBtn
                visible: !card.toast
                anchors.right: parent.right
                anchors.top: parent.top
            }

            Column {
                id: textCol
                anchors.left: card.showIcon ? iconTile.right : parent.left
                anchors.leftMargin: card.showIcon ? 10 : 0
                anchors.right: card.toast ? parent.right : closeBtn.left
                anchors.rightMargin: card.toast ? 4 : 8
                anchors.top: parent.top
                spacing: 2

                Item {
                    width: parent.width
                    height: summary.implicitHeight

                    Text {
                        id: summary
                        anchors.left: parent.left
                        anchors.right: timeLabel.visible ? timeLabel.left : parent.right
                        anchors.rightMargin: timeLabel.visible ? 8 : 0
                        renderType: Text.NativeRendering
                        font.hintingPreference: Font.PreferNoHinting
                        text: card.notification ? card.notification.summary : ""
                        color: DrawerTheme.primary
                        font.family: Fonts.ui
                        font.pixelSize: 14
                        font.weight: Font.Medium
                        elide: Text.ElideRight
                    }
                    Text {
                        id: timeLabel
                        visible: card.timeText !== ""
                        anchors.right: parent.right
                        anchors.baseline: summary.baseline
                        renderType: Text.NativeRendering
                        font.hintingPreference: Font.PreferNoHinting
                        text: card.timeText
                        color: DrawerTheme.secondary
                        font.family: Fonts.ui
                        font.pixelSize: 12
                        font.features: { "tnum": 1 }
                    }
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
        }

        Row {
            width: layout.width
            visible: card.hasActions
            spacing: 8

            Repeater {
                model: card.hasActions ? card.notification.actions : []
                delegate: Rectangle {
                    id: actionPill
                    required property var modelData
                    height: 28
                    radius: 10
                    width: actionLabel.implicitWidth + 24
                    // A card, like the drawers' buttons.
                    color: actionArea.containsMouse ? DrawerTheme.cardHover : DrawerTheme.card
                    Behavior on color { ColorAnimation { duration: 120 } }

                    // Border and glass SWAP rather than stack: at rest
                    // the pill keeps the plain 1px ring that has always
                    // been its only resting shape, and on hover that
                    // ring steps aside for the lens' own edge. Drawing
                    // both would put two lines on the same silhouette.
                    //
                    // Never in a toast, whichever state it is in -- see
                    // `toast` at the top of this file.
                    readonly property bool lit: !card.toast && actionArea.containsMouse
                    border.width: 0


                    Text {
                        id: actionLabel
                        anchors.centerIn: parent
                        renderType: Text.NativeRendering
                        font.hintingPreference: Font.PreferNoHinting
                        text: actionPill.modelData.text
                        color: DrawerTheme.primary
                        font.family: Fonts.ui
                        font.pixelSize: 13
                    }
                    MouseArea {
                        id: actionArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: card.actionRequested(actionPill.modelData)
                    }
                }
            }
        }
    }

    component CloseCross: Item {
        width: 20
        height: 20

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
}
