import QtQuick
import "../theme"

// The bar's battery gauge: an outline with the charge inset inside it and
// a nub on the right, the classic battery drawing. It replaced the filled
// pill (a body at 30% under a solid fill), which read as a white block
// once the battery was full; outlined, a full battery stays a drawing.
// The percentage sits beside it, in Battery.qml, in the band's one text
// style; the charging or plug glyph sits after it, also in Battery.qml.
// BatteryIcon.qml (BatteryAlert's card) is a separate, larger gauge.
//
// No colour of its own: `color` is whatever Battery.qml's batteryColor
// resolves to (primary ink, charging green, conservation blue, low red or
// amber), so the gauge follows the band's light/dark material flip like
// every other module.
Item {
    id: root

    property real percent: 100   // 0-100
    property color color: Ink.primary
    // Where the charge will stop, 0-100, or negative for none. Set to 60
    // by Battery.qml while conservation mode caps the cell: a dotted line
    // across the inside of the outline, where the fill will stop.
    property real capAt: -1

    readonly property real bodyWidth: 26
    readonly property real bodyHeight: 13
    readonly property real bodyRadius: 4
    readonly property real stroke: 1.2
    // The fill sits inside the stroke with a hairline of air around it.
    readonly property real inset: 2
    readonly property real innerWidth: root.bodyWidth - root.inset * 2
    readonly property real innerHeight: root.bodyHeight - root.inset * 2

    implicitWidth: root.bodyWidth + 1.5 + nub.width
    implicitHeight: root.bodyHeight

    // The outline, at 55% so the fill stays the strongest thing.
    Rectangle {
        width: root.bodyWidth
        height: root.bodyHeight
        radius: root.bodyRadius
        color: "transparent"
        border.width: root.stroke
        border.color: Qt.rgba(root.color.r, root.color.g, root.color.b, 0.55)
    }

    // The charge, as wide as the percentage of the inside.
    Rectangle {
        x: root.inset
        y: root.inset
        width: root.innerWidth * Math.max(0, Math.min(1, root.percent / 100))
        height: root.innerHeight
        radius: 2
        color: root.color
    }

    // The cap: three dots stacked across the inside, at the stop.
    Column {
        visible: root.capAt >= 0
        x: Math.round(root.inset + root.innerWidth * root.capAt / 100)
        y: root.inset + 0.5
        spacing: 1.2
        Repeater {
            model: 4
            Rectangle {
                width: 1
                height: 1.2
                color: Qt.rgba(root.color.r, root.color.g, root.color.b, 0.55)
            }
        }
    }

    // Terminal nub, at the outline's 55%.
    Rectangle {
        id: nub
        x: root.bodyWidth + 1.5
        y: (root.bodyHeight - height) / 2
        width: 2
        height: 5
        topRightRadius: 1
        bottomRightRadius: 1
        color: Qt.rgba(root.color.r, root.color.g, root.color.b, 0.55)
    }
}
