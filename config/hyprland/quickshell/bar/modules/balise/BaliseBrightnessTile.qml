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

    // The fill is a FULL tile-shaped rectangle in the fill colour, of
    // which only the bottom slice shows -- the clip is the level. That
    // makes it exactly the tile's shape cut by a straight line: the
    // bottom corners follow the tile's own curve at every level (at 1% a
    // thin sliver hugging it, not a square-cornered bar), and the top
    // corners appear by themselves as the slice reaches the top. The
    // previous per-corner radii shrank the bottom ones toward 0 at low
    // levels while the top ones behaved, which is the asymmetry asked
    // about. Strictly proportional: 1% is 1% of the height.
    Item {
        id: fill
        anchors.bottom: parent.bottom
        width: parent.width
        height: tile.hdrActive ? 0 : parent.height * Math.max(0, Math.min(1, tile.level))
        clip: true
        Behavior on height { enabled: !drag.pressed; NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

        Rectangle {
            anchors.bottom: parent.bottom
            width: tile.width
            height: tile.height
            radius: tile.radius
            color: DrawerTheme.on
        }
    }

    Text {
        id: sun
        anchors.horizontalCenter: parent.horizontalCenter
        y: parent.height - 14 - height
        renderType: Text.NativeRendering
        font.hintingPreference: Font.PreferNoHinting
        text: ""   // mgc sun
        // Dark while the fill covers it, light on the bare track below it.
        color: tile.hdrActive ? DrawerTheme.secondary
             : (fill.height >= tile.height - sun.y ? DrawerTheme.onInk : DrawerTheme.primary)
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
        function apply(my) { OsdState.setBrightness((height - my) / height); }
        onPressed: (m) => apply(m.y)
        onPositionChanged: (m) => { if (pressed) apply(m.y); }
        onWheel: (w) => OsdState.setBrightness(tile.level + (w.angleDelta.y > 0 ? 0.05 : -0.05))
    }
}
