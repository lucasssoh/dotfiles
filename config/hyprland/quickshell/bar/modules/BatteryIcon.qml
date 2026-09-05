import QtQuick
import "../theme"

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
    // Overlays a pulsing bolt when true -- ph-lightning (0xe2de), the
    // SAME glyph/color (#ffcc00) Performance.qml already uses for its
    // own "performance" power-profile state, reused verbatim rather
    // than picking a new charging color out of nowhere.
    property bool charging: false

    implicitWidth: 22
    implicitHeight: 11

    readonly property real nubWidth: Math.max(1, height * 0.16)
    readonly property real nubHeight: height * 0.5
    readonly property real bodyWidth: width - nubWidth - 1
    readonly property real borderWidth: Math.max(1, height * 0.14)

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
    // overlaps or visually thickens it. `inset` is derived from
    // `root.height`, NOT this Rectangle's own `height` below -- that
    // would be a binding loop (height depends on inset, inset would
    // depend on height).
    Rectangle {
        readonly property real inset: root.borderWidth + Math.max(1, root.height * 0.15)
        x: inset
        y: inset
        width: Math.max(0, (root.bodyWidth - inset * 2) * Math.max(0, Math.min(1, root.percent / 100)))
        height: root.height - inset * 2
        radius: Math.max(0, body.radius - inset)
        color: root.fillColor
    }

    // Pulsing bolt overlay, centered over the whole glyph (body + fill)
    // -- same convention as macOS/phone battery icons showing a bolt
    // through the outline when plugged in, rather than a separate badge
    // off to the side (no room for one at this icon's usual sizes
    // anyway). The pulse (not a static bolt) is what actually reads as
    // "charging in progress" rather than "charging icon exists". White,
    // not Performance.qml's own yellow (#ffcc00, the first pass here) --
    // asked back to white once seen against the light green the
    // outline/fill also turn while charging (Battery.qml's own
    // isCharging branch): yellow-on-green read worse than white-on-green
    // does.
    Text {
        visible: root.charging
        anchors.centerIn: parent
        renderType: Text.NativeRendering
        font.hintingPreference: Font.PreferNoHinting
        text: ""
        color: "#f2f2f7"
        font.family: Fonts.iconPhosphorBold
        font.pixelSize: root.height * 0.95
        SequentialAnimation on opacity {
            running: root.charging
            loops: Animation.Infinite
            NumberAnimation { from: 1.0; to: 0.35; duration: 700; easing.type: Easing.InOutQuad }
            NumberAnimation { from: 0.35; to: 1.0; duration: 700; easing.type: Easing.InOutQuad }
        }
    }
}
