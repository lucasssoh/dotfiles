import QtQuick
import "../../theme"

// The one control this drawer is made of, used five ways: the output
// master, the input master, and a row per application in either
// direction. Everything that differs between those is a property --
// there is no second slider anywhere in here.
//
// It reports, it does not own. `value` is bound from the node and
// `moved()` is emitted on every change; the PARENT writes it back to
// `node.audio.volume` and the new value arrives back through the binding.
// Keeping a local "position" that the drag mutates and the binding fights
// is the classic way to get a slider that stutters when something else
// (a media key, the OSD, the module's own scroll wheel) moves the same
// volume while a finger is on it.
Item {
    id: root

    property real value: 0
    // 1.0 for outputs and for applications -- the boost headroom above
    // 100% came out of AudioOutput.qml's scroll handler for going unused,
    // and a slider whose right-hand third is a region nobody wants is
    // worse than a shorter slider.
    //
    // Inputs keep 1.5 (AudioInput.qml's own cap, still there): mic gain
    // above unity is the one place the headroom does real work, on a
    // laptop array that is quiet by construction.
    property real maximum: 1.0
    property bool muted: false
    // 0..1 live level, drawn as a hairline under the track. -1 means
    // "this row has no meter", which is every row except the two masters
    // -- see MixerState's own note on why peak monitoring is not free.
    property real peak: -1
    property color accent: Ink.accent

    signal moved(real v)

    // The meter, when there is one, sits under the track and needs the
    // room -- see its Rectangle below.
    implicitHeight: root.peak >= 0 ? 18 : 14

    readonly property real knobRadius: 6
    readonly property real travel: Math.max(1, root.width - root.knobRadius * 2)
    // Clamped both ends: a source left at 1.5 by something else while
    // `maximum` is 1.0 would otherwise push the knob past the right edge.
    readonly property real t: Math.max(0, Math.min(1, root.value / root.maximum))
    readonly property real knobX: root.knobRadius + root.t * root.travel

    // Muted is drawn, not disabled. The slider still moves while muted --
    // that is how every mixer behaves and it is the useful behaviour
    // (set the level you want, then unmute) -- so the greying is a
    // statement about the audio, not about the control.
    readonly property color liveColor: root.muted ? Ink.faint : root.accent

    Rectangle {
        id: track
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        height: 6
        radius: 3
        color: Surfaces.cardHover
    }

    // Unity mark, only on the tracks that go past it. Without it a mic at
    // 100% sits at an arbitrary-looking two thirds and there is nothing on
    // screen to say that position means anything.
    Rectangle {
        visible: root.maximum > 1.0
        width: 1
        height: 6
        radius: 0
        color: Qt.rgba(1, 1, 1, 0.22)
        x: root.knobRadius + (1.0 / root.maximum) * root.travel
        anchors.verticalCenter: track.verticalCenter
    }

    Rectangle {
        id: fill
        anchors.left: track.left
        anchors.verticalCenter: track.verticalCenter
        width: root.knobX
        height: track.height
        radius: track.radius
        color: root.liveColor
        Behavior on color { ColorAnimation { duration: 120 } }
    }

    // The meter. Deliberately BELOW the track and 2px tall rather than
    // painted inside it: a level drawn in the same groove as the volume
    // reads as a second, contradictory volume, and the eye cannot tell
    // which of the two edges is the one it can drag.
    //
    // No Behavior on its width. Peak arrives at the graph's own rate and
    // is meant to twitch -- smoothing it is how a level meter turns into
    // a slow bar that says nothing about transients.
    Rectangle {
        visible: root.peak >= 0
        anchors.left: track.left
        anchors.top: track.bottom
        anchors.topMargin: 2
        width: Math.max(0, Math.min(1, root.peak)) * root.width
        height: 2
        radius: 1
        color: root.accent
        opacity: root.muted ? 0.18 : 0.45
    }

    Rectangle {
        id: knob
        width: root.knobRadius * 2
        height: root.knobRadius * 2
        radius: root.knobRadius
        x: root.knobX - root.knobRadius
        anchors.verticalCenter: track.verticalCenter
        color: Ink.primary
        // Grows under the pointer and while dragging, which is the only
        // feedback a 12px circle can give that it is the thing being held.
        scale: drag.pressed ? 1.25 : (drag.containsMouse ? 1.12 : 1.0)
        Behavior on scale { NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }
    }

    MouseArea {
        id: drag
        anchors.fill: parent
        // Vertical slack: the row is 14px tall and the track 6, so without
        // this the grab target is a hairline. -6/+6 makes it the height of
        // the card's own line without changing anything drawn.
        anchors.topMargin: -6
        anchors.bottomMargin: -6
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor

        function apply(mx) {
            const v = (mx - root.knobRadius) / root.travel;
            root.moved(Math.max(0, Math.min(1, v)) * root.maximum);
        }

        onPressed: (m) => drag.apply(m.x)
        onPositionChanged: (m) => { if (drag.pressed) drag.apply(m.x); }
        // Same 5% step the two bar modules use for their own scroll, so
        // the wheel does the same thing whether it is over the pill or
        // over this.
        onWheel: (w) => {
            const step = w.angleDelta.y > 0 ? 0.05 : -0.05;
            root.moved(Math.max(0, Math.min(root.maximum, root.value + step)));
        }
    }
}
