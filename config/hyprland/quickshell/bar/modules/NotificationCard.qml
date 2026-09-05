import QtQuick
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
// Same glass recipe as Osd.qml/BatteryAlert.qml (2-stop vertical
// Gradient + two GlassRim children) -- see Osd.qml's header for why this
// is "glass" in look without being real compositor blur. Height is
// content-driven (body text length varies notification to notification),
// unlike Osd/BatteryAlert's fixed literal heights -- `layout` below has
// no bottom anchor, so its implicit height drives `card.height` with no
// feedback loop (layout's own height never depends on card's).
Rectangle {
    id: card

    required property var notification
    signal dismissRequested()
    signal actionRequested(var action)

    readonly property bool critical: card.notification
        && card.notification.urgency === NotificationUrgency.Critical
    readonly property color accent: card.critical ? "#ff6e6e" : "#a8b4c4"
    readonly property bool hasImage: card.notification && card.notification.image !== ""
    readonly property bool hasActions: card.notification && card.notification.actions.length > 0
    readonly property bool hasBody: card.notification && card.notification.body !== ""

    width: 340
    radius: 16
    height: layout.height + 28

    gradient: Gradient {
        GradientStop { position: 0.0; color: "#ff3f4450" }
        GradientStop { position: 1.0; color: "#ff060608" }
    }
    GlassRim { cornerRadius: card.radius }
    GlassRim { cornerRadius: card.radius; lightOrigin: "bottomRight"; strength: 0.45 }

    Column {
        id: layout
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 14
        spacing: 8

        Item {
            id: headerRow
            width: layout.width
            height: Math.max(iconTile.height, textCol.height, closeBtn.height)

            Rectangle {
                id: iconTile
                anchors.left: parent.left
                anchors.top: parent.top
                width: 28
                height: 28
                radius: 8
                color: "#1a1d2a"

                Image {
                    anchors.fill: parent
                    anchors.margins: 2
                    visible: card.hasImage
                    fillMode: Image.PreserveAspectCrop
                    source: card.hasImage ? card.notification.image : ""
                }
                Text {
                    visible: !card.hasImage
                    anchors.centerIn: parent
                    renderType: Text.NativeRendering
                    font.hintingPreference: Font.PreferNoHinting
                    text: ""   // ph-bell -- generic fallback when no image/icon
                    color: card.accent
                    font.family: Fonts.iconPhosphor
                    font.pixelSize: 14
                }
            }

            Item {
                id: closeBtn
                anchors.right: parent.right
                anchors.top: parent.top
                width: 20
                height: 20

                Rectangle {
                    anchors.centerIn: parent
                    width: 12
                    height: 1.5
                    radius: 1
                    color: Qt.rgba(1, 1, 1, 0.5)
                    rotation: 45
                }
                Rectangle {
                    anchors.centerIn: parent
                    width: 12
                    height: 1.5
                    radius: 1
                    color: Qt.rgba(1, 1, 1, 0.5)
                    rotation: -45
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: card.dismissRequested()
                }
            }

            Column {
                id: textCol
                anchors.left: iconTile.right
                anchors.leftMargin: 10
                anchors.right: closeBtn.left
                anchors.rightMargin: 8
                anchors.top: parent.top
                spacing: 2

                Text {
                    width: parent.width
                    renderType: Text.NativeRendering
                    font.hintingPreference: Font.PreferNoHinting
                    text: card.notification ? card.notification.summary : ""
                    color: "#f2f2f7"
                    font.family: Fonts.ui
                    font.pixelSize: 14
                    font.bold: true
                    elide: Text.ElideRight
                }
                Text {
                    width: parent.width
                    visible: card.hasBody
                    renderType: Text.NativeRendering
                    font.hintingPreference: Font.PreferNoHinting
                    text: card.hasBody ? card.notification.body : ""
                    color: Qt.rgba(1, 1, 1, 0.7)
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
                    radius: 14
                    width: actionLabel.implicitWidth + 20
                    color: actionArea.containsMouse ? "#14161d" : "transparent"
                    border.width: 1
                    border.color: Qt.rgba(1, 1, 1, 0.18)
                    Behavior on color { ColorAnimation { duration: 120 } }

                    Text {
                        id: actionLabel
                        anchors.centerIn: parent
                        renderType: Text.NativeRendering
                        font.hintingPreference: Font.PreferNoHinting
                        text: actionPill.modelData.text
                        color: "#f2f2f7"
                        font.family: Fonts.ui
                        font.pixelSize: 12
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
}
