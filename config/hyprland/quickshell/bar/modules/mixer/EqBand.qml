import QtQuick
import "../../theme"

// One band of the equalizer: a vertical fader that reads in dB, centred on
// zero. Five of these across the card, one per filter in
// config/pipewire/50-equalizer.conf.
//
// Centred rather than filled from the bottom, and that is the whole reason
// it is not MixerSlider turned on its side. A volume slider runs 0..100 and
// its fill means "how much"; a band runs -12..+12 and its fill means "how
// far from flat, and which way". Drawing it from the bottom would make a
// flat curve look like five sliders turned all the way down.
//
// It reports, it does not own -- same contract as MixerSlider: `value` is
// bound from MixerState and every change goes out through `moved()`, so
// nothing here can drift from what the filter chain actually holds.
Item {
    id: band

    property string label: ""
    property real value: 0
    property real range: 12
    // Greyed, but still draggable: setting a curve with the equalizer off
    // and then switching it on is a reasonable way to work, and a control
    // that refuses input while showing a value is just a lie about being
    // interactive.
    property bool active: true
    property color accent: Ink.accent

    signal moved(real db)

    readonly property real knobRadius: 6
    readonly property real travel: Math.max(1, track.height - band.knobRadius * 2)
    readonly property real t: Math.max(-1, Math.min(1, band.value / band.range))
    // y of the knob centre: t = +1 at the top, -1 at the bottom.
    readonly property real knobY: track.y + band.knobRadius + (1 - band.t) / 2 * band.travel

    readonly property color liveColor: band.active ? band.accent : Ink.faint

    // dB readout on top. Fixed height so the five columns stay aligned
    // whatever their values, and no decimals: a tenth of a dB is below what
    // anyone can hear on a band this wide, and it would make the number
    // jitter on every frame of a drag.
    Text {
        id: readout
        anchors.top: parent.top
        anchors.horizontalCenter: parent.horizontalCenter
        renderType: Text.NativeRendering
        font.hintingPreference: Font.PreferNoHinting
        text: (band.value > 0 ? "+" : "") + Math.round(band.value)
        color: Math.round(band.value) === 0 ? Ink.muted : band.liveColor
        font.family: Fonts.ui
        font.pixelSize: 10
        Behavior on color { ColorAnimation { duration: 120 } }
    }

    Rectangle {
        id: track
        anchors.top: readout.bottom
        anchors.topMargin: 5
        anchors.bottom: caption.top
        anchors.bottomMargin: 6
        anchors.horizontalCenter: parent.horizontalCenter
        width: 4
        radius: 2
        color: Surfaces.cardHover
    }

    // The zero line, drawn across the whole column rather than just the
    // track: it is the reference the five bands share, and a tick confined
    // to a 4px groove does not read as one line across the card.
    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        y: track.y + track.height / 2
        height: 1
        color: Qt.rgba(1, 1, 1, 0.10)
    }

    // The fill, from the zero line to the knob, in whichever direction.
    Rectangle {
        x: track.x
        width: track.width
        y: Math.min(band.knobY, track.y + track.height / 2)
        height: Math.abs(band.knobY - (track.y + track.height / 2))
        radius: track.radius
        color: band.liveColor
        Behavior on color { ColorAnimation { duration: 120 } }
    }

    Rectangle {
        id: knob
        width: band.knobRadius * 2
        height: band.knobRadius * 2
        radius: band.knobRadius
        x: track.x + track.width / 2 - band.knobRadius
        y: band.knobY - band.knobRadius
        color: band.active ? Ink.primary : Ink.muted
        scale: drag.pressed ? 1.25 : (drag.containsMouse ? 1.12 : 1.0)
        Behavior on scale { NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }
    }

    Text {
        id: caption
        anchors.bottom: parent.bottom
        anchors.horizontalCenter: parent.horizontalCenter
        renderType: Text.NativeRendering
        font.hintingPreference: Font.PreferNoHinting
        text: band.label
        color: Ink.secondary
        font.family: Fonts.ui
        font.pixelSize: 10
    }

    // The whole column is the grab target, not the 4px track -- the columns
    // are ~50px apart, so there is no neighbour close enough for this to
    // steal from, and a fader you have to hit within two pixels is not a
    // fader.
    MouseArea {
        id: drag
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor

        function apply(my) {
            const rel = (my - track.y - band.knobRadius) / band.travel;   // 0 top, 1 bottom
            band.moved((1 - 2 * Math.max(0, Math.min(1, rel))) * band.range);
        }

        onPressed: (m) => drag.apply(m.y)
        onPositionChanged: (m) => { if (drag.pressed) drag.apply(m.y); }
        // Double click flattens this band alone. The section header's own
        // reset does all five; this is for the one that went too far.
        onDoubleClicked: band.moved(0)
        // 1 dB a notch. The 5% of a volume slider makes no sense on a
        // signed scale, and a dB is the unit the number above is in.
        onWheel: (w) => {
            const step = w.angleDelta.y > 0 ? 1 : -1;
            band.moved(Math.max(-band.range, Math.min(band.range, band.value + step)));
        }
    }
}
