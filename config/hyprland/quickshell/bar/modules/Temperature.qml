import QtQuick
import "../theme"
import "../services"

// Native port of waybar's `temperature` module. Same simplification as
// the original inline one-liner: hardcoded to thermal_zone0. Sampling
// lives in the shared SystemStats singleton now -- see its header for
// why (one bar instance per monitor, temperature is the same number on
// every screen).

Item {
    id: root

    // Fixed width, not Math.max(label.implicitWidth, ...) -- that
    // reactive form made the pill visibly grow/shrink every time
    // celsius crossed a digit boundary. valueMetrics measures the
    // worst-case string ONCE with the real font instead.
    TextMetrics {
        id: valueMetrics
        font.family: Fonts.ui
        font.pixelSize: 13
        text: "100"   // padStart(3) never exceeds 3 digits
    }

    implicitWidth: iconGlyph.implicitWidth + label.spacing + valueMetrics.width + 20
    implicitHeight: 24

    Row {
        id: label
        anchors.centerIn: parent
        spacing: 4

        // History on this Row's alignment: per-glyph size bumps, plain
        // top-alignment (Row's default), and anchors.baseline were each
        // right for a DIFFERENT icon font, not universally -- Nerd Font +
        // Inter happened to sit close enough at y:0; Font Awesome (drawn
        // like a letter, sitting ON the baseline) needed
        // anchors.baseline; Phosphor's glyphs are drawn floating,
        // vertically centered in their own line box rather than sitting
        // on the baseline -- box-centering (anchors.verticalCenter, both
        // items) is what actually measures aligned for THIS font, tested
        // pixel-precise against baseline-anchoring before picking it.
        // Moral: there's no one correct anchor mode across icon fonts,
        // has to be re-checked (screenshot, not assumed) per swap.
        Text {
            id: iconGlyph
            renderType: Text.NativeRendering
            font.hintingPreference: Font.PreferNoHinting
            anchors.verticalCenter: parent.verticalCenter
            text: ""   // ph-thermometer
            color: SystemStats.tempCelsius >= 85 ? "#ff6e6e" : "#f2f2f7"
            font.family: Fonts.iconPhosphor
            font.pixelSize: 15
        }
        // waybar format: "{temperatureC:>3}" -- right-padded to 3 chars,
        // no unit (asked to keep it that way).
        Text {
            id: valueLabel
            renderType: Text.NativeRendering
            font.hintingPreference: Font.PreferNoHinting
            anchors.verticalCenter: parent.verticalCenter
            text: String(SystemStats.tempCelsius).padStart(3, " ")
            color: SystemStats.tempCelsius >= 85 ? "#ff6e6e" : "#f2f2f7"
            font.family: Fonts.ui
            font.pixelSize: 13
        }
    }
}
