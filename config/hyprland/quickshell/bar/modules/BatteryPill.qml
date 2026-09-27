import QtQuick
import "../theme"

// The bar's battery since the HyperOS pass: a filled pill with the
// percentage written INSIDE it, the HyperOS status-bar battery, in place
// of BatteryIcon's outlined iOS/macOS gauge with the number beside it.
// BatteryIcon.qml stays as it is -- BatteryAlert's card still draws with
// it, and a gauge is the right picture there.
//
// Three layers, back to front:
//   - the body, the state colour at 30%: the empty part of the cell,
//     fainter past `capAt` (Lenovo conservation mode) when one is set;
//   - the fill, the state colour, as wide as the charge;
//   - the percentage, twice -- see below.
//
// No colour of its own: `color` is whatever Battery.qml's batteryColor
// resolves to (primary ink, charging green, conservation blue, low red or
// amber), and the number's two inks are the island's own `primary` and
// `onLight`, so the pill follows the band's light/dark material flip like
// every other module.
Item {
    id: root

    property real percent: 100   // 0-100
    property color color: Ink.primary
    // Number over the empty part, and over the fill. `onFill` is the
    // island's inverse ink: dark on the usual light fill, light again when
    // the material flips and the fill goes dark.
    property color numberOnEmpty: Ink.primary
    property color numberOnFill: Ink.onLight
    // Where the charge will stop, 0-100, or negative for no tick. Set to
    // 60 by Battery.qml while conservation mode caps the cell.
    property real capAt: -1

    readonly property real bodyWidth: 28
    readonly property real bodyHeight: 14
    readonly property real bodyRadius: 4.5
    readonly property real fillWidth: root.bodyWidth * Math.max(0, Math.min(1, root.percent / 100))

    implicitWidth: root.bodyWidth + 1.5 + nub.width
    implicitHeight: root.bodyHeight

    // The empty part of the cell. Split in two at `capAt` when a cap is
    // set: up to the cap at the usual 30%, beyond it at 10% -- the part of
    // the cell the charge will never reach under conservation mode reads
    // as "not available" without any mark crossing the percentage. (A
    // tick was tried first: at 60% of a 28px pill it always lands under
    // the second digit and reads as a stroke through it.) With no cap the
    // first half simply spans the whole body.
    readonly property real capWidth: root.capAt >= 0
        ? Math.round(root.bodyWidth * root.capAt / 100) : root.bodyWidth

    Rectangle {
        id: body
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

    // The percentage, drawn TWICE and split exactly on the fill's edge,
    // the same overdraw BatteryIcon.qml uses for its '+': whole in the
    // empty-part ink, then again in the fill ink clipped to the fill's
    // box. Neither ink survives both backgrounds, and the split moves
    // with the charge, so a fixed colour would vanish on one side.
    Text {
        id: number
        width: root.bodyWidth
        height: root.bodyHeight
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        // CurveRendering, not the NativeRendering every other bar Text
        // uses (asked for: "un peu plus anti-aliasé"). At 10px native
        // rasterisation snaps the digits to the pixel grid and they read
        // blocky inside the pill; the curve renderer antialiases the
        // outline itself, in greyscale. QtRendering (distance field) was
        // tried too and fringed the digits in colour.
        renderType: Text.CurveRendering
        font.hintingPreference: Font.PreferNoHinting
        text: Math.round(root.percent)
        color: root.numberOnEmpty
        font.family: Fonts.ui
        font.pixelSize: 10
        font.weight: Font.DemiBold
        font.features: { "tnum": 1 }
    }
    Item {
        width: root.fillWidth
        height: root.bodyHeight
        clip: true

        Text {
            width: number.width
            height: number.height
            horizontalAlignment: number.horizontalAlignment
            verticalAlignment: number.verticalAlignment
            renderType: number.renderType
            font: number.font
            text: number.text
            color: root.numberOnFill
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
