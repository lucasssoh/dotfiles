import QtQuick

// Custom-drawn battery glyph -- a rounded-rect OUTLINE with a small
// terminal nub on the right (the classic iOS/macOS system battery icon:
// reference screenshot showed their widget's version, a rounded body +
// nub with a proportional colored fill inside) and a FILL sized to the
// exact percentage, not a fixed discrete tier. Asked for specifically
// because Battery.qml's/BatteryAlert.qml's previous icon (a Phosphor
// font glyph) only ever has ~5 fixed shapes (full/high/medium/low/
// empty) -- fine for the bar's own tiny module, wrong for anything
// meant to read as an exact gauge. No icon font gives a continuously
// variable fill, so this is hand-drawn instead, the same way Osd.qml's
// own level track/fill or GlassRim.qml's rim are: plain Rectangles, no
// image assets.
//
// Outline and fill are separate colors on purpose (both default to the
// same neutral platinum used everywhere else in this bar, `#f2f2f7`):
// Battery.qml's own top-bar module keeps them equal, matching its
// existing "no charge-level coloring, ever" rule (see that file's own
// comment) -- only BatteryAlert.qml's warning tiers actually diverge the
// two, tinting the fill (and there, the outline too) amber/red.
Item {
    id: root

    property real percent: 100   // 0-100
    property color outlineColor: "#f2f2f7"
    property color fillColor: "#f2f2f7"
    property real outlineOpacity: 0.7
    // Overlays a static '+' when true (see the overlay below) -- two
    // Rectangles, not the ph-lightning glyph earlier passes drew here:
    // at the 20x10 the bar renders this at, the bolt's diagonals never
    // resolved into a bolt, they just muddied the fill.
    property bool charging: false
    // The '+' is drawn TWICE in two colors, split on the fill's own box
    // (see the overlay below): dark where it lies on the filled part,
    // battery-colored where it lies on the empty part -- neither color
    // survives both backgrounds, and the split moves with the charge.
    property color plusOnFill: "#3a3a3c"
    property color plusOnEmpty: root.fillColor

    implicitWidth: 22
    implicitHeight: 11

    readonly property real nubWidth: Math.max(1, height * 0.16)
    readonly property real nubHeight: height * 0.5
    readonly property real bodyWidth: width - nubWidth - 1
    readonly property real borderWidth: Math.max(1, height * 0.14)

    // Fill geometry, hoisted to root because the '+' overlay below has
    // to clip itself to exactly this box. `fillInset` is derived from
    // `root.height`, NOT from the fill Rectangle's own height -- that
    // would be a binding loop (height depends on inset, inset would
    // depend on height).
    readonly property real fillInset: borderWidth + Math.max(1, height * 0.15)
    readonly property real fillWidth: Math.max(0, (bodyWidth - fillInset * 2)
        * Math.max(0, Math.min(1, percent / 100)))

    // Shared by both copies of the '+' so they cannot drift apart. The
    // arm is sized to the fill's own inner height so the mark can sit
    // entirely INSIDE the fill: any taller and its top/bottom tips poke
    // out past a full fill and stay light, which reads as debris rather
    // than as a mark.
    readonly property real plusArm: Math.max(2, (height - fillInset * 2) * 0.95)
    readonly property real plusThickness: Math.max(1, height * 0.16)

    // Body outline -- border only, transparent inside, so the fill
    // Rectangle below shows through instead of sitting on top of a
    // second fill.
    Rectangle {
        id: body
        x: 0
        y: 0
        width: root.bodyWidth
        height: root.height
        radius: height * 0.32
        color: "transparent"
        border.width: root.borderWidth
        border.color: root.outlineColor
        opacity: root.outlineOpacity
    }

    // Terminal nub, vertically centered on the body.
    Rectangle {
        x: root.bodyWidth + 1
        y: (root.height - root.nubHeight) / 2
        width: root.nubWidth
        height: root.nubHeight
        radius: width * 0.4
        color: root.outlineColor
        opacity: root.outlineOpacity
    }

    // Proportional fill, inset from the outline's own border so it never
    // overlaps or visually thickens it (geometry lives on root above).
    Rectangle {
        x: root.fillInset
        y: root.fillInset
        width: root.fillWidth
        height: root.height - root.fillInset * 2
        radius: Math.max(0, body.radius - root.fillInset)
        color: root.fillColor
    }

    // Charging mark: a plain '+', centered on the BODY rather than on
    // this Item -- the icon is NOT symmetric (the terminal nub eats
    // `nubWidth + 1` on the right), so centering on root's own width
    // pushes the mark visibly right of where the battery reads as
    // centered. Both copies below are laid out against the body box for
    // exactly that reason.
    //
    // A single color does not work here, because the mark straddles two
    // backgrounds whose split MOVES with the charge: the light fill
    // wherever the battery is filled, the empty body everywhere else.
    // Dark grey disappears on the empty side, the battery color
    // disappears on the fill. So the same mark is drawn twice: once in
    // full in the battery color, then again in dark on top, clipped to
    // exactly the fill Rectangle's box. Whatever the fill covers is
    // dark, everything else keeps the battery color, and the seam is the
    // fill's own edge -- so it reads as the fill passing behind the
    // mark, not as two marks.
    //
    // Overdraw, not two complementary clips, because the mark is taller
    // than the fill box: the arms that overshoot it vertically have to
    // stay light too, and here they do for free.
    component ChargePlus: Item {
        property color barColor: "#000000"

        Rectangle {
            anchors.centerIn: parent
            width: root.plusArm
            height: root.plusThickness
            color: parent.barColor
        }

        Rectangle {
            anchors.centerIn: parent
            width: root.plusThickness
            height: root.plusArm
            color: parent.barColor
        }
    }

    ChargePlus {
        visible: root.charging
        x: 0
        y: 0
        width: root.bodyWidth
        height: root.height
        barColor: root.plusOnEmpty
    }

    // Dark copy, clipped to the fill. Its ChargePlus is laid out against
    // the same body box and merely shifted back by the clipper's own
    // position, so the two copies stay pixel-aligned however the fill
    // edge falls across them.
    Item {
        visible: root.charging
        x: root.fillInset
        y: root.fillInset
        width: root.fillWidth
        height: root.height - root.fillInset * 2
        clip: true

        ChargePlus {
            x: -root.fillInset
            y: -root.fillInset
            width: root.bodyWidth
            height: root.height
            barColor: root.plusOnFill
        }
    }
}
