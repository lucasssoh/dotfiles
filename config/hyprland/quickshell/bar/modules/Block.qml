import QtQuick

// Visual capsule matching waybar/style.css's grouping: several modules
// glued into one pill (shared background, 4px rounding on the block's
// own outer corners -- since it's a single Rectangle, not several,
// there's no "inner seam" to fake). Waybar's per-block color pairs
// (background/border) are passed in per instance in shell.qml, copied
// straight from the @define-color values there.
//
// Border is on all 4 sides (Rectangle.border), not the top/bottom-only
// style.css originally had -- deliberate departure, asked for.

Rectangle {
    id: block
    default property alias content: row.children
    property color borderColor: "#505050"

    implicitWidth: row.implicitWidth
    implicitHeight: 24
    radius: 4
    // Defensive: a child that doesn't center/size itself exactly right
    // (square corners against these rounded ones, or a background a
    // pixel taller than 24) would otherwise visibly poke past the
    // pill's rounded edge instead of just being invisible overflow.
    clip: true

    border.width: 1
    border.color: block.borderColor

    Row {
        id: row
        anchors.fill: parent
        spacing: 0
    }
}
