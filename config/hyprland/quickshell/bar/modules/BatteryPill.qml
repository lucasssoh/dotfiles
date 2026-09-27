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
//   - the percentage, white with a dark outline -- see below.
//
// No colour of its own: `color` is whatever Battery.qml's batteryColor
// resolves to (primary ink, charging green, conservation blue, low red or
// amber), so the pill follows the band's light/dark material flip like
// every other module. The number is the one fixed colour -- see there.
Item {
    id: root

    property real percent: 100   // 0-100
    property color color: Ink.primary
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

    // The percentage: ONE colour, white, with a thin dark outline.
    //
    // It used to be drawn twice and split on the fill's edge (dark over
    // the fill, light over the empty part). Asked for instead: a single
    // colour that holds against white, black AND grey -- the pill's fill
    // is the primary ink (white on the dark band, black on the light one)
    // and its empty part is that ink at 30%, a mid grey. Measured, no
    // flat colour can: the best neutral reaches ~4:1 on white and black
    // but ~1:1 on the grey, and the best saturated one (a violet) is
    // 4.3/4.1:1 and still only 1.2:1 on the grey, readable by hue alone.
    // An outline sidesteps the maths: the white body carries the black
    // background, the dark rim carries the white and grey ones, and it
    // survives the state colours (charging green, low red...) too.
    //
    // CurveRendering (asked for: "un peu plus anti-aliasé") -- at 10px
    // native rasterisation snaps the digits to the pixel grid and they
    // read blocky; the curve renderer antialiases the outline in
    // greyscale. QtRendering (distance field) fringed them in colour.
    property color numberColor: "#f2f2f7"
    property color numberOutline: "#0c0c0e"

    Text {
        id: number
        width: root.bodyWidth
        height: root.bodyHeight
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        renderType: Text.CurveRendering
        font.hintingPreference: Font.PreferNoHinting
        text: Math.round(root.percent)
        color: root.numberColor
        style: Text.Outline
        styleColor: root.numberOutline
        font.family: Fonts.ui
        font.pixelSize: 10
        font.weight: Font.Bold
        font.features: { "tnum": 1 }
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
