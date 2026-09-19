import QtQuick
import "../theme"

// The rounded-square icon badge a drawer control carries: accent-tinted
// while its control is on, a flat neutral otherwise.
//
// Extracted from DrawerTile.qml when BaliseHome's SYSTEM rows (Night
// mode, HDR, Dark mode, Screenshot) gained icons too -- asked for, "des
// icones de meme style que les connectivite". That is the whole point of
// the request: the badge has to be the SAME object as the one on the
// tiles above, not a second one that looks like it today and drifts
// tomorrow. Three call sites now (DrawerTile, ToggleRow, ActionRow).
//
// Collapses to nothing when `glyph` is empty, so a control with no icon
// costs no layout rather than drawing an empty square.
Rectangle {
    id: badge

    property string glyph: ""
    property bool active: false
    property color accent: Ink.accent

    visible: badge.glyph !== ""
    width: 30
    height: 30
    radius: 9
    color: badge.active ? Surfaces.accentStrong : Surfaces.cardHover
    Behavior on color { ColorAnimation { duration: 120 } }

    Text {
        anchors.centerIn: parent
        renderType: Text.NativeRendering
        font.hintingPreference: Font.PreferNoHinting
        text: badge.glyph
        color: badge.active ? badge.accent : Ink.primary
        font.family: Fonts.iconPhosphor
        font.pixelSize: 17
    }
}
