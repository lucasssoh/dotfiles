import QtQuick
import "../../theme"
import ".."          // GlassCard
import "../balise"   // RevealPop

// One line in a device picker: pick this sink, or pick this source. No
// slider -- the level belongs to whichever device is CURRENT, and it is
// on the master card above; putting one here would offer to set the
// volume of an output nothing is playing to.
//
// Shorter and flatter than MixerRow on purpose. The picker is a list of
// alternatives to the card above it, and drawing its entries as cards of
// the same weight would read as five equal things rather than one choice
// and its options.
Rectangle {
    id: dev

    property int revealIndex: 0
    RevealPop { item: dev; index: dev.revealIndex; fromScale: 1.0 }

    property string glyph: ""
    property string title: ""
    property bool current: false

    signal picked()

    width: parent ? parent.width : 0
    height: 34
    radius: 10

    layer.enabled: hit.containsMouse
    layer.effect: GlassCard { radius: 10 }

    // The current entry gets no fill at all, only the tick on the right.
    // It was given the lit `accentSoft` treatment first and that was
    // wrong: in a list whose whole job is "click one of these", a
    // highlighted row reads as the recommended action rather than as the
    // one already in effect.
    color: hit.containsMouse ? Surfaces.cardHover : "transparent"
    Behavior on color { ColorAnimation { duration: 120 } }

    MouseArea {
        id: hit
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        // Re-picking what is already default is a no-op in pipewire, but
        // it also closes the picker (MixerState.setSink does), which is
        // the useful reading of clicking the current row.
        onClicked: dev.picked()
    }

    Text {
        id: devIcon
        anchors.left: parent.left
        anchors.leftMargin: 12
        anchors.verticalCenter: parent.verticalCenter
        renderType: Text.NativeRendering
        font.hintingPreference: Font.PreferNoHinting
        text: dev.glyph
        color: dev.current ? Ink.accent : Ink.secondary
        font.family: Fonts.iconPhosphor
        font.pixelSize: 14
    }

    Text {
        anchors.left: devIcon.right
        anchors.leftMargin: 10
        anchors.right: tick.left
        anchors.rightMargin: 8
        anchors.verticalCenter: parent.verticalCenter
        renderType: Text.NativeRendering
        font.hintingPreference: Font.PreferNoHinting
        text: dev.title
        color: dev.current ? Ink.primary : Ink.secondary
        font.family: Fonts.ui
        font.pixelSize: 12
        elide: Text.ElideRight
    }

    Text {
        id: tick
        anchors.right: parent.right
        anchors.rightMargin: 12
        anchors.verticalCenter: parent.verticalCenter
        visible: dev.current
        renderType: Text.NativeRendering
        font.hintingPreference: Font.PreferNoHinting
        text: "\uE06C"   // lu-check
        color: Ink.accent
        font.family: Fonts.iconPhosphor
        font.pixelSize: 14
    }
}
