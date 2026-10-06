import QtQuick
import "../../theme"

// A small choice: on (inverted), off (outlined), or `hinted` (a dashed
// outline: seen by Boussole, not yet confirmed).
Rectangle {
    id: chip

    property string text: ""
    property bool on: false
    property bool hinted: false
    signal clicked()

    height: 32
    width: Math.max(32, label.implicitWidth + 22)
    radius: height / 2
    color: chip.on ? DrawerTheme.on : (hit.containsMouse ? DrawerTheme.cardHover : "transparent")
    border.width: chip.on || chip.hinted ? 0 : 1
    border.color: DrawerTheme.faint
    // Like Balise's controls: the state change eases, the press gives.
    Behavior on color { ColorAnimation { duration: 120 } }
    scale: hit.pressed ? 0.96 : 1
    Behavior on scale { NumberAnimation { duration: 90; easing.type: Easing.OutCubic } }

    Canvas {
        anchors.fill: parent
        visible: chip.hinted && !chip.on
        onPaint: {
            const c = getContext("2d");
            c.reset();
            c.setLineDash([3, 3]);
            c.strokeStyle = DrawerTheme.secondary;
            c.lineWidth = 1;
            c.beginPath();
            c.roundedRect(0.5, 0.5, width - 1, height - 1, height / 2, height / 2);
            c.stroke();
        }
    }

    Text {
        id: label
        anchors.centerIn: parent
        text: chip.text
        color: chip.on ? DrawerTheme.onInk : DrawerTheme.primary
        Behavior on color { ColorAnimation { duration: 120 } }
        font.family: Fonts.ui
        font.pixelSize: 13
        font.weight: Font.DemiBold
        renderType: Text.NativeRendering
        font.hintingPreference: Font.PreferNoHinting
    }

    MouseArea {
        id: hit
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: chip.clicked()
    }
}
