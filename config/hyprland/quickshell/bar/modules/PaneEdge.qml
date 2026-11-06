import QtQuick
import "../theme"

// The edge of a glass pane, drawn over it: a hairline rim all round and
// a brighter line just inside the top, where the light catches. Replaces
// the convex GlassLens on the panes (asked for: lighter, "exactement comme
// dans la maquette"); the lens is still what the cards in the central
// island wear.
//
// Fill its pane and give it the pane's radii. Per-corner, because the
// side sheets are only rounded on the side that meets the desktop.
Item {
    id: edge

    property real radius: 0
    property real topLeftRadius: edge.radius
    property real topRightRadius: edge.radius
    property real bottomLeftRadius: edge.radius
    property real bottomRightRadius: edge.radius

    anchors.fill: parent

    Rectangle {
        anchors.fill: parent
        color: "transparent"
        topLeftRadius: edge.topLeftRadius
        topRightRadius: edge.topRightRadius
        bottomLeftRadius: edge.bottomLeftRadius
        bottomRightRadius: edge.bottomRightRadius
        border.width: 1
        border.color: DrawerTheme.paneRim
    }

    // The top light: a second ring one pixel in, kept to the top band so
    // it fades out down the corners instead of tracing the whole pane.
    Item {
        x: 1
        y: 1
        width: Math.max(0, edge.width - 2)
        height: Math.max(0, Math.min(edge.height - 2, Math.max(edge.topLeftRadius, edge.topRightRadius, 12)))
        clip: true

        Rectangle {
            width: parent.width
            height: Math.max(0, edge.height - 2)
            color: "transparent"
            topLeftRadius: Math.max(0, edge.topLeftRadius - 1)
            topRightRadius: Math.max(0, edge.topRightRadius - 1)
            bottomLeftRadius: Math.max(0, edge.bottomLeftRadius - 1)
            bottomRightRadius: Math.max(0, edge.bottomRightRadius - 1)
            border.width: 1
            border.color: DrawerTheme.paneHighlight
        }
    }
}
