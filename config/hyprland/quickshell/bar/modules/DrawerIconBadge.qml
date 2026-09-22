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
        // A TWO-glyph badge -- PowerHome's double bolt, the only one so
        // far -- does not fit at the single-glyph size. Every Lucide
        // glyph carries a full 1.0em advance (verified in the font's own
        // hmtx: advance == unitsPerEm for zap, battery-charging and the
        // rest), so a pair at 17px spans 34 inside a 30px square and
        // spills out of the rounded corners.
        //
        // Tightening the pair rather than just shrinking it is what keeps
        // it looking like the other badges: Lucide inks thin, and taking
        // the glyphs down far enough to fit on advance alone would make
        // these two strokes visibly lighter than every neighbouring icon.
        // At 14 with -2 the pair measures 26 and the stroke stays close.
        font.pixelSize: badge.glyph.length > 1 ? 14 : 17
        // Qt adds letterSpacing after the LAST character too, so the
        // Text is 2px wider than the ink and centerIn would sit the pair
        // 1px left. Given back here.
        font.letterSpacing: badge.glyph.length > 1 ? -2 : 0
        anchors.horizontalCenterOffset: badge.glyph.length > 1 ? 1 : 0
    }
}
