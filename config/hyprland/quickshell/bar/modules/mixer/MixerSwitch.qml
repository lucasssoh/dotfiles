import QtQuick
import "../../theme"

// The bar's switch. Same 40x22 track and 18px thumb BaliseSectionList's
// master toggle and NotificationCenter's DND button both draw, lifted into
// a file rather than copied a third time -- "every switch in this bar is
// literally the same control" is the rule those two already follow, and a
// third hand-rolled copy is how that stops being true.
//
// Deliberately NOT re-pointed at the other two: they are inside a row that
// is itself the click target, so their MouseArea covers the whole card.
// This one is a control of its own in a header.
Item {
    id: sw

    property bool checked: false
    property color accent: Ink.accent
    signal toggled(bool value)

    implicitWidth: 40
    implicitHeight: 22

    Rectangle {
        id: track
        anchors.fill: parent
        radius: height / 2
        color: sw.checked ? sw.accent : Qt.rgba(1, 1, 1, 0.18)
        Behavior on color { ColorAnimation { duration: 120 } }

        Rectangle {
            width: 18
            height: 18
            radius: 9
            color: "#0c0c0e"
            anchors.verticalCenter: parent.verticalCenter
            x: sw.checked ? parent.width - width - 2 : 2
            Behavior on x { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
        }
    }

    MouseArea {
        anchors.fill: parent
        // The track is 22px tall in a section header; a few pixels of slack
        // makes it a comfortable target without changing anything drawn.
        anchors.margins: -4
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: sw.toggled(!sw.checked)
    }
}
