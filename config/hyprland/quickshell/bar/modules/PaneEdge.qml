import QtQuick
import "../theme"

// The edge of a glass pane, drawn over it: a hairline rim all round and
// a brighter line just inside the top, where the light catches. Replaces
// the convex GlassLens on the panes (asked for: lighter, "exactement comme
// dans la maquette"); the lens is still what the cards in the central
// island wear.
//
// Fill its pane and give it the pane's radii, per corner.
//
// The side sheets turn both lines down: `highlight: false`, since one line
// 1px under the rim, on a radius 1px smaller, read as a doubled edge, and
// `fade: true`, a rim bright at the top that is gone before the bottom.
Item {
    id: edge

    property real radius: 0
    property real topLeftRadius: edge.radius
    property real topRightRadius: edge.radius
    property real bottomLeftRadius: edge.radius
    property real bottomRightRadius: edge.radius
    property bool highlight: true
    property bool fade: false

    anchors.fill: parent

    // The faded rim, in plain Rectangles: a Shape with a gradient fill did
    // the same in one piece, but CurveRenderer prepared it on the CPU
    // when the sheet was created, right as its slide began, and the
    // first frames stuttered. The rim is whole down to 20% of the height
    // (the top corners with it, their radii are far shorter than that),
    // then each side is a 1px line fading out by 85%.
    Item {
        visible: edge.fade
        width: edge.width
        height: Math.round(edge.height * 0.2)
        clip: true

        Rectangle {
            width: edge.width
            height: edge.height
            color: "transparent"
            topLeftRadius: edge.topLeftRadius
            topRightRadius: edge.topRightRadius
            bottomLeftRadius: edge.bottomLeftRadius
            bottomRightRadius: edge.bottomRightRadius
            border.width: 1
            border.color: DrawerTheme.paneRim
        }
    }
    Repeater {
        model: edge.fade ? [0, edge.width - 1] : []

        Rectangle {
            required property real modelData
            x: modelData
            y: Math.round(edge.height * 0.2)
            width: 1
            height: Math.round(edge.height * 0.65)
            gradient: Gradient {
                GradientStop { position: 0.0; color: DrawerTheme.paneRim }
                GradientStop { position: 1.0; color: DrawerTheme.clear(DrawerTheme.paneRim) }
            }
        }
    }

    Rectangle {
        visible: !edge.fade
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
        visible: edge.highlight
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
