import QtQuick
import "../theme"

// The bar's battery gauge: a filled pill with a dimmer body behind the
// charge. When conservation mode is active, the unused part beyond its
// limit is dimmer again. The percentage and mains mark live in Battery.qml.
//
// No colour of its own: `color` is whatever Battery.qml's batteryColor
// resolves to (primary ink, charging green, conservation blue, low red or
// amber), so the pill follows the band's light/dark material flip like
// every other module.
Item {
    id: root

    property real percent: 100   // 0-100
    property color color: Ink.primary
    // Where the charge will stop, 0-100, or negative for none. Set to 60
    // by Battery.qml while conservation mode caps the cell; the segment
    // beyond the limit is dimmed.
    property real capAt: -1

    readonly property real bodyWidth: 26
    readonly property real bodyHeight: 13
    readonly property real bodyRadius: 4
    readonly property real fillWidth: root.bodyWidth * Math.max(0, Math.min(1, root.percent / 100))

    implicitWidth: root.bodyWidth + 1.5 + nub.width
    implicitHeight: root.bodyHeight

    // The empty cell is split at the charge limit: the part beyond it is
    // dimmer, so the limit reads without a mark across the charge.
    readonly property real capWidth: root.capAt >= 0
        ? Math.round(root.bodyWidth * root.capAt / 100) : root.bodyWidth

    Item {
        width: root.bodyWidth
        height: root.bodyHeight

        Rectangle {
            width: root.capWidth
            height: root.bodyHeight
            topLeftRadius: root.bodyRadius
            bottomLeftRadius: root.bodyRadius
            topRightRadius: Math.max(0, root.bodyRadius - (root.bodyWidth - root.capWidth))
            bottomRightRadius: Math.max(0, root.bodyRadius - (root.bodyWidth - root.capWidth))
            color: Qt.rgba(root.color.r, root.color.g, root.color.b, 0.30)
        }
        Rectangle {
            visible: root.capAt >= 0
            x: root.capWidth
            width: root.bodyWidth - root.capWidth
            height: root.bodyHeight
            topRightRadius: root.bodyRadius
            bottomRightRadius: root.bodyRadius
            color: Qt.rgba(root.color.r, root.color.g, root.color.b, 0.10)
        }

        Rectangle {
            width: root.fillWidth
            height: root.bodyHeight
            topLeftRadius: root.bodyRadius
            bottomLeftRadius: root.bodyRadius
            topRightRadius: Math.max(0, root.bodyRadius - (root.bodyWidth - root.fillWidth))
            bottomRightRadius: Math.max(0, root.bodyRadius - (root.bodyWidth - root.fillWidth))
            color: root.color
        }
    }

    // Terminal nub, at 55% so it reads as part of the cell without
    // competing with the fill.
    Rectangle {
        id: nub
        x: root.bodyWidth + 1.5
        y: (root.bodyHeight - height) / 2
        width: 2
        height: 5
        topRightRadius: 1.5
        bottomRightRadius: 1.5
        color: Qt.rgba(root.color.r, root.color.g, root.color.b, 0.55)
    }
}
