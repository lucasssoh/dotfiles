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
// NOT the glass recipe Osd.qml/BatteryAlert.qml use (2-stop vertical
// Gradient + two GlassRim children, see Osd.qml's header) -- notification
// cards are deliberately the one flat, matte surface in this bar. Asked
// for in two steps: first for the toasts alone ("les popups notifs ne
// doivent pas avoir d'effet metallique"), then for the center's history
// too ("il faut aussi le même style non metalic dans les notifcenter").
// The `glass` opt-out property that briefly existed between those two is
// gone with the second one -- one consumer's exception is worth a knob,
// both consumers agreeing is just the look.
//
// What made it read as brushed metal was the #3f4450 top stop raking to
// near-black under two specular rims. Flat #1e2128 instead: the drawer
// pane's own top stop (DrawerIsland.drawerFillTop), so in the center the
// card is the same material as the pane it sits on, and it stays opaque
// over that translucent pane (theme/Surfaces.qml's rule). Height is
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

    // No `gradient` at all now, which is also the only way to actually
    // get rid of one: Rectangle.gradient is a QJSValue that accepts a
    // Gradient object or a preset, so assigning `null` to switch a
    // gradient off is silently dropped -- no warning in quickshell's log
    // -- and the old gradient keeps painting. That cost a debugging pass
    // when the matte variant was still a runtime opt-out; the fix then
    // was two gradient stops collapsing to one colour, and now that both
    // consumers want matte there is simply no gradient to declare.
    // Toast mode: pure black -- asked for ("un fond noir pure sobre sans
    // bordure"). A popup that appears unbidden over whatever you are
    // doing has a different job from a card sitting in a panel you
    // opened on purpose: it has to be read in one glance and then
    // forgotten, and every gram of decoration on it works against that.
    property bool toast: false

    color: card.toast ? "#ff000000" : "#ff1e2128"

    // The card itself carries NO glass edge in either mode. It shows
    // text; it is not a button. The rule the whole bar follows now is
    // that the glass marks something you can press -- so on this card it
    // is the action pills and the close button that light up, never the
    // surface they sit on. `toast` therefore only changes the fill.


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
                    text: "\uE059"   // lu-bell -- generic fallback when no image/icon
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
                    border.width: actionPill.lit ? 0 : 1
                    border.color: Qt.rgba(1, 1, 1, 0.18)

                    layer.enabled: actionPill.lit
                    layer.effect: GlassChip { radius: 14 }

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
