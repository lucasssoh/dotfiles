import QtQuick
import "../theme"
import "balise"   // RevealPop

// The square-ish toggle card used in a drawer's tile grid: icon badge,
// bold title, quiet status line under it, whole card clickable.
//
// Extracted verbatim from BaliseHome.qml's own `component Tile` when
// PowerHome.qml became the third drawer on toolsIsland and needed the
// same card for its charge-limit and power-profile controls. BaliseHome
// now aliases this (`component Tile: DrawerTile {}`) rather than keeping
// its own copy, so its call sites are untouched and the two drawers can
// never drift into two subtly different cards -- the same argument
// SystemStats.qml's header makes for centralizing the samplers.
//
// The one change made in the move: `accent` is a property here, defaulted
// to Ink.accent, where the inline version reached out to BaliseHome's own
// `root.accent` (which was itself `Ink.accent`). Same color, no call site
// affected, and a drawer that wants a different one can now say so.
Rectangle {
    id: tile

    property int revealIndex: 0
    RevealPop { item: tile; index: tile.revealIndex }

    property string title: ""
    property string status: ""
    property string glyph: ""
    property bool active: false
    property color accent: Ink.accent
    signal activated()
    // Right-click opens this tile's section list (WiFi/Bluetooth in
    // Balise); a tile with no second action routes both to the same
    // place, or leaves this unconnected.
    signal activatedSecondary()

    radius: 20

    // Same glass edge every other block in this bar now carries -- see
    // GlassCard.qml. Only while this is HOVERED or ON: the glass is a
    // state cue, not decoration, so a zone nobody is touching and nothing
    // has switched on carries no edge at all. It also means the layer is
    // allocated only for the one element in play.
    layer.enabled: tile.active || mouseArea.containsMouse
    layer.effect: GlassCard { radius: 20 }
    // "On" needs real contrast at rest, not just a tinted icon/status --
    // a faint accent-tinted fill plus an accent border, subtle enough to
    // still read as a card rather than a solid switch. Hover darkens or
    // brightens slightly from whichever base it is already in.
    color: tile.active
        ? (mouseArea.containsMouse ? Surfaces.accentStrongest : Surfaces.accentMedium)
        : (mouseArea.containsMouse ? Surfaces.cardHover : Surfaces.cardDeep)
    border.width: 1
    border.color: tile.active ? tile.accent : Qt.rgba(1, 1, 1, 0.18)
    Behavior on color { ColorAnimation { duration: 120 } }
    Behavior on border.color { ColorAnimation { duration: 120 } }

    readonly property color fg: tile.active ? tile.accent : Ink.primary

    // Vertically centered rather than top-anchored with a fixed margin:
    // tiles differ in whether they carry a status line, and centering
    // makes both cases sit correctly without hand-tuning a height per
    // tile. Anchored on BOTH sides, not just the left -- `elide` needs a
    // real width to work against, and without one a long value (a 30-char
    // SSID) runs past the tile's edge instead of ellipsizing.
    Column {
        id: tileText
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: 16
        anchors.rightMargin: 12
        anchors.verticalCenter: parent.verticalCenter
        spacing: 8

        // The glyph sits in its own rounded-square badge rather than
        // floating bare above the label. Moved out to
        // DrawerIconBadge.qml when BaliseHome's SYSTEM rows needed the
        // same badge -- see that file.
        DrawerIconBadge {
            glyph: tile.glyph
            active: tile.active
            accent: tile.accent
        }
        Text {
            width: tileText.width
            renderType: Text.NativeRendering
            font.hintingPreference: Font.PreferNoHinting
            text: tile.title
            color: Ink.primary
            font.family: Fonts.ui
            font.pixelSize: 13
            font.bold: true
            elide: Text.ElideRight
        }
        Text {
            width: tileText.width
            visible: tile.status !== ""
            renderType: Text.NativeRendering
            font.hintingPreference: Font.PreferNoHinting
            text: tile.status
            color: tile.active ? tile.fg : Ink.secondary
            font.family: Fonts.ui
            font.pixelSize: 11
            elide: Text.ElideRight
        }
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        cursorShape: Qt.PointingHandCursor
        onClicked: (mouse) => {
            if (mouse.button === Qt.RightButton) tile.activatedSecondary();
            else tile.activated();
        }
    }
}
