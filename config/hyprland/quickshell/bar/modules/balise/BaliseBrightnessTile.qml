import QtQuick
import "../../theme"
import "../../services"

// Brightness as a tall tile beside the connectivity grid -- the HyperOS
// control-centre column (the "tuile verticale" of the mockups). Same
// gauge as BaliseScreenRow's, turned upright: the fill rises from the
// bottom and IS the handle, with a straight top edge (the level; a round
// end melted into the track at low levels) that only rounds as it reaches
// the top. The sun sits in the bottom disc the fill never shrinks below,
// the percentage at the top.
//
// Drag or scroll to set, through OsdState.setBrightness (brightnessctl,
// one call in flight); OsdState.brightness, which the keys also keep
// current, is what it shows. HDR locks it: greyed, "HDR", no input.
Rectangle {
    id: tile

    property bool hdrActive: false
    property int revealIndex: 0

    RevealPop { item: tile; index: tile.revealIndex }

    readonly property real level: OsdState.brightness

    radius: 20
    color: DrawerTheme.cardRaised

    Connections {
        target: BaliseState
        function onPanelOpenChanged() {
            if (BaliseState.panelOpen) OsdState.readBrightness();
        }
    }
    Component.onCompleted: OsdState.readBrightness()

    Rectangle {
        id: fill
        anchors.bottom: parent.bottom
        width: parent.width
        // Starts at the sun's square, the level spreads over the rest.
        height: tile.hdrActive ? width
              : width + (parent.height - width) * Math.max(0, Math.min(1, tile.level))
        bottomLeftRadius: tile.radius
        bottomRightRadius: tile.radius
        topLeftRadius: Math.max(0, tile.radius - (parent.height - fill.height))
        topRightRadius: Math.max(0, tile.radius - (parent.height - fill.height))
        color: tile.hdrActive ? "#3a3a3e" : DrawerTheme.on
        Behavior on height { enabled: !drag.pressed; NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
        Behavior on color { ColorAnimation { duration: 140 } }
    }

    Text {
        anchors.horizontalCenter: parent.horizontalCenter
        y: parent.height - (parent.width + height) / 2
        renderType: Text.NativeRendering
        font.hintingPreference: Font.PreferNoHinting
        text: ""   // mgc sun
        color: tile.hdrActive ? DrawerTheme.secondary : DrawerTheme.onInk
        font.family: Fonts.iconMingcute
        font.pixelSize: 20
    }

    Text {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: 12
        renderType: Text.NativeRendering
        font.hintingPreference: Font.PreferNoHinting
        text: tile.hdrActive ? "HDR" : Math.round(tile.level * 100)
        // On the dark track, or on the white fill once it reaches the top.
        color: tile.hdrActive ? DrawerTheme.secondary
             : (fill.height > parent.height - 36 ? DrawerTheme.onInk : DrawerTheme.primary)
        font.family: Fonts.ui
        font.pixelSize: 13
        font.weight: Font.Medium
        font.features: { "tnum": 1 }
    }

    MouseArea {
        id: drag
        anchors.fill: parent
        enabled: !tile.hdrActive
        cursorShape: tile.hdrActive ? Qt.ArrowCursor : Qt.PointingHandCursor
        // Inverse of the fill's height: the bottom `width` px are the
        // sun's square, the level spreads over the rest.
        function apply(my) {
            OsdState.setBrightness((height - my - width) / Math.max(1, height - width));
        }
        onPressed: (m) => apply(m.y)
        onPositionChanged: (m) => { if (pressed) apply(m.y); }
        onWheel: (w) => OsdState.setBrightness(tile.level + (w.angleDelta.y > 0 ? 0.05 : -0.05))
    }
}
