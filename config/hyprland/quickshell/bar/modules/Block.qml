import QtQuick

// Visual capsule matching waybar/style.css's grouping: several modules
// glued into one pill (shared background, rounded on the block's own
// outer corners -- since it's a single Rectangle, not several, there's
// no "inner seam" to fake). Waybar's per-block color pairs
// (background/border) are passed in per instance in shell.qml, copied
// straight from the @define-color values there.
//
// No border, on purpose: the earlier "verre givré" glass rim is gone --
// each block is now defined purely by its own fill (deepened black
// #0c0c0e / graphite-platinum #34383f, see shell.qml's header comment)
// against whatever's behind the bar, no outline needed.

Rectangle {
    id: block
    default property alias content: row.children
    // Set on the single leftmost/rightmost Block instance in shell.qml
    // (the bar's own panel now sits flush against all 3 screen edges,
    // margins: 0 -- see its header comment) -- squares off that block's
    // own outer-bottom corner too, so it doesn't round away from an edge
    // it's otherwise flush against on the other 3 sides.
    property bool squareLeft: false
    property bool squareRight: false
    // true (default) for the main bar's own Block, which sits flush
    // against the screen's top edge -- a rounded top corner there would
    // just cut a visible notch out of the screen edge instead of reading
    // as attached to it. false for any Block that floats independently
    // WITH a gap from the top (e.g. the metrics pill in shell.qml) -- it
    // gets normal rounded top corners like every other side, since it's
    // not actually touching that edge.
    property bool flushTop: true
    // Overridable per instance (e.g. the main bar's own island Block in
    // shell.qml, asked for a bit more roundness than every other pill).
    // Named cornerRadius, not radius, to avoid shadowing Rectangle's own
    // built-in `radius` property (unused here -- this component always
    // sets the 4 per-corner radii individually instead, see below).
    property real cornerRadius: 10

    implicitWidth: row.implicitWidth
    implicitHeight: 24
    // 4 -> 10 (still short of a full pill -- 12 at this 24px height).
    // Per-corner radius properties need Qt 6.7+ (this machine: Qt 6.11).
    topLeftRadius: flushTop ? 0 : cornerRadius
    topRightRadius: flushTop ? 0 : cornerRadius
    bottomLeftRadius: squareLeft ? 0 : cornerRadius
    bottomRightRadius: squareRight ? 0 : cornerRadius
    // Defensive: a child that doesn't center/size itself exactly right
    // (square corners against these rounded ones, or a background a
    // pixel taller than 24) would otherwise visibly poke past the
    // pill's rounded edge instead of just being invisible overflow.
    clip: true

    // left + verticalCenter, not anchors.fill: parent -- lets an instance
    // override `height` (e.g. the main bar in shell.qml, taller than its
    // 24px content so it sits closer to where tiled windows start,
    // matching the metrics/tools pills' own proximity) and have its
    // content stay vertically centered in the extra space instead of
    // clinging to the top with dead space below. Identical result to
    // `anchors.fill` when height == implicitHeight (24), i.e. every other
    // Block instance -- purely additive.
    Row {
        id: row
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        spacing: 0
    }
}
