import QtQuick
import "../theme"

// The bar's battery gauge since the HyperOS pass: a FILLED pill -- the
// empty part of the cell tinted, the charge solid -- in place of
// BatteryIcon's outlined iOS/macOS gauge. BatteryIcon.qml stays as it is
// for BatteryAlert's card.
//
// The percentage briefly lived inside this pill, HyperOS-style, and came
// back out to Battery.qml's own slot on the left: at the bar's size a
// 10px number split across two inks was hard to read ("difficile de trop
// voir la batterie"). The gauge carries the level, the number beside it
// carries the value.
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
    // by Battery.qml while conservation mode caps the cell.
    property real capAt: -1

    readonly property real bodyWidth: 22
    readonly property real bodyHeight: 11
    readonly property real bodyRadius: 3.5
    readonly property real fillWidth: root.bodyWidth * Math.max(0, Math.min(1, root.percent / 100))

    implicitWidth: root.bodyWidth + 1.5 + nub.width
    implicitHeight: root.bodyHeight

    // The empty part of the cell. Split in two at `capAt` when a cap is
    // set: up to the cap at the usual 30%, beyond it at 10% -- the part of
    // the cell the charge will never reach under conservation mode reads
    // as "not available" without any extra mark. With no cap the first
    // half simply spans the whole body.
    readonly property real capWidth: root.capAt >= 0
        ? Math.round(root.bodyWidth * root.capAt / 100) : root.bodyWidth

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

    // Square on its right edge -- that edge is the charge level -- until
    // it runs into the body's own rounded end, where its corners round
    // with it. `bodyWidth - fillWidth` is how far the level still is from
    // that end, so the right radii grow from 0 to the body's radius over
    // the last few pixels instead of snapping. No clip needed, which a
    // plain `clip: true` could not do anyway: it clips to the bounding
    // box, not to the body's rounded shape.
    Rectangle {
        width: root.fillWidth
        height: root.bodyHeight
        topLeftRadius: root.bodyRadius
        bottomLeftRadius: root.bodyRadius
        topRightRadius: Math.max(0, root.bodyRadius - (root.bodyWidth - root.fillWidth))
        bottomRightRadius: Math.max(0, root.bodyRadius - (root.bodyWidth - root.fillWidth))
        color: root.color
    }

    // Terminal nub, at 55% so it reads as part of the cell without
    // competing with the fill.
    Rectangle {
        id: nub
        x: root.bodyWidth + 1.5
        y: (root.bodyHeight - height) / 2
        width: 2
        height: 4
        topRightRadius: 1.5
        bottomRightRadius: 1.5
        color: Qt.rgba(root.color.r, root.color.g, root.color.b, 0.55)
    }
}
