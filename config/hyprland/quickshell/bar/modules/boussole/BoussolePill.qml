import QtQuick
import "../../theme"

// A button of the drawer: filled ("on") for the main action, outlined
// otherwise.
Rectangle {
    id: pill

    property string text: ""
    property bool primary: false
    signal clicked()

    height: 40
    width: label.implicitWidth + 30
    radius: height / 2
    color: pill.primary ? (hit.containsMouse ? Qt.rgba(DrawerTheme.on.r, DrawerTheme.on.g, DrawerTheme.on.b, 0.88) : DrawerTheme.on)
                        : (hit.containsMouse ? DrawerTheme.cardHover : Qt.rgba(DrawerTheme.cardHover.r, DrawerTheme.cardHover.g, DrawerTheme.cardHover.b, 0))
    border.width: pill.primary ? 0 : 1
    border.color: DrawerTheme.faint
    // Like Balise's controls: the state change eases, the press gives.
    // The idle fill is cardHover at zero alpha, not "transparent": that
    // is transparent BLACK, and easing from it ran through grey.
    Behavior on color { ColorAnimation { duration: 120 } }
    scale: hit.pressed ? 0.97 : 1
    Behavior on scale { NumberAnimation { duration: 90; easing.type: Easing.OutCubic } }

    Text {
        id: label
        anchors.centerIn: parent
        text: pill.text
        color: pill.primary ? DrawerTheme.onInk : DrawerTheme.primary
        Behavior on color { ColorAnimation { duration: 120 } }
        font.family: Fonts.ui
        font.pixelSize: 14
        font.weight: Font.DemiBold
        renderType: Text.NativeRendering
        font.hintingPreference: Font.PreferNoHinting
    }

    MouseArea {
        id: hit
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: pill.clicked()
    }
}
