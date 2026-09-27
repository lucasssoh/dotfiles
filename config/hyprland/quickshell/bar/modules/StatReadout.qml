import QtQuick
import "../theme"

// One metric reading as TEXT ONLY: a value and its unit, one style --
// "38°C", "3.5GB", "1.9GHz". The unit follows the value's ink (so a
// reading past its danger threshold turns red as a whole).
//
// HyperOS pass: the METRICS block used to open every reading with a
// glyph (chip, thermometer, memory stick...). The unit already says what
// the number is, so the glyph was the part repeating it; dropping it is
// most of what makes the block read quieter. Shared here so Cpu,
// Temperature, Memory, Fan and Traffic cannot drift apart in size,
// weight or spacing.
//
// Fixed width, same rule the glyph+value modules had: the value's slot is
// sized on `widest` (the widest string it can ever show) and the value is
// right-aligned inside it, so a changing number never moves the unit, the
// readings next to it, or the edge of the block.
Item {
    id: root

    property string value: ""
    property string unit: ""
    property string widest: root.value
    property color valueColor: Ink.primary
    // Same ink as the value by default -- see the unit Text below.
    property color unitColor: root.valueColor

    implicitWidth: valueMetrics.width + unitText.implicitWidth + 1
    implicitHeight: 24

    TextMetrics {
        id: valueMetrics
        font: valueText.font
        text: root.widest
    }

    Text {
        id: valueText
        renderType: Text.NativeRendering
        font.hintingPreference: Font.PreferNoHinting
        anchors.right: unitText.left
        anchors.rightMargin: 1
        anchors.verticalCenter: parent.verticalCenter
        width: valueMetrics.width
        horizontalAlignment: Text.AlignRight
        text: root.value
        color: root.valueColor
        font.family: Fonts.ui
        font.pixelSize: 13
        font.weight: Font.Medium
        font.features: { "tnum": 1 }
    }

    Text {
        id: unitText
        renderType: Text.NativeRendering
        font.hintingPreference: Font.PreferNoHinting
        anchors.right: parent.right
        anchors.baseline: valueText.baseline
        // Same size, weight and ink as the value (asked for: no accent
        // difference between value and unit). It started smaller and in
        // the secondary ink.
        text: root.unit
        color: root.unitColor
        font.family: Fonts.ui
        font.pixelSize: 13
        font.weight: Font.Medium
    }
}
