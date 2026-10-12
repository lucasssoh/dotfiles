import QtQuick
import "../theme"

// A thin scroll bar beside a Flickable (a ListView too), for long lists:
// 4 px, wider under the pointer. Drag the thumb, or click the track to
// jump there. Shown only when there is something to scroll.
Item {
    id: bar

    required property Flickable target
    readonly property real span: Math.max(0, bar.target.contentHeight - bar.target.height)
    readonly property bool active: hit.containsMouse || hit.pressed

    visible: bar.span > 1
    width: 12

    Rectangle {
        id: thumb
        anchors.horizontalCenter: parent.horizontalCenter
        width: bar.active ? 8 : 4
        radius: width / 2
        height: Math.max(32, bar.height * bar.target.height / Math.max(1, bar.target.contentHeight))
        y: bar.span > 0 ? (bar.height - thumb.height) * Math.max(0, Math.min(1, (bar.target.contentY - bar.target.originY) / bar.span)) : 0
        color: DrawerTheme.ink(bar.active ? 0.55 : bar.target.moving ? 0.38 : 0.2)
        Behavior on width { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
        Behavior on color { ColorAnimation { duration: 120 } }
    }

    MouseArea {
        id: hit
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        property real grab: 0

        function scrollTo(top) {
            const room = bar.height - thumb.height;
            const f = room > 0 ? Math.max(0, Math.min(1, top / room)) : 0;
            bar.target.contentY = bar.target.originY + f * bar.span;
        }
        onPressed: m => {
            const on = m.y >= thumb.y && m.y <= thumb.y + thumb.height;
            hit.grab = on ? m.y - thumb.y : thumb.height / 2;
            if (!on) hit.scrollTo(m.y - hit.grab);
        }
        onPositionChanged: m => { if (hit.pressed) hit.scrollTo(m.y - hit.grab); }
        onWheel: w => {
            bar.target.contentY = Math.max(bar.target.originY, Math.min(bar.target.originY + bar.span, bar.target.contentY - w.angleDelta.y));
        }
    }
}
