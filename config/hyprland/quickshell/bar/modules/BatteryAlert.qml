import QtQuick
import "../theme"
import "../services"

// Low-battery alert -- laid out around a Figma-AI-generated mockup
// (reference screenshot: rounded card, a rounded-square icon TILE at
// top holding a battery glyph, a big "{percent}% battery remaining"
// headline, then two FULL-WIDTH PILL buttons -- not text-link rows
// behind hairline dividers, this alert's previous shape after an even
// earlier iOS-dialog-verbatim pass). Each pill carries a small circular
// icon badge on its right edge (check / x), same as the reference. The
// mockup's own subtitle line ("Activate low consumption mode") is gone
// -- once the button below it said "Power save mode" instead of a
// generic "Activate mode", the two were just repeating each other.
//
// Pills are transparent at rest, filled only on hover (asked for
// explicitly: "pas de bg si pas hover") -- the mockup's own pills are
// always filled, diverged from on purpose here. Reads as a plain
// text+badge row until you're actually about to click one, at which
// point the same dark #14161d hover fill lands. Both pills now share
// the EXACT same shape/border/hover-fade recipe, right down to that
// fill color (asked for explicitly: "prend exactement le style de not
// now" -- a slightly-green variant of it was tried and then asked back
// out again). Primary's accent (platinum/critical red) still lives on
// the battery glyph and its check badge, just not on the pill itself.
//
// Colors are this bar's OWN platinum palette, not the mockup's --
// the mockup's violet was just whatever Figma's AI defaulted to
// (nothing was asked for on its end), so it never belonged. `accent`
// below is `#a8b4c4`, the exact desaturated blue-to-platinum token
// shell.qml's own header describes replacing this bar's old neon
// accent2 with everywhere else; `#ff6e6e` (critical, and the X badge)
// is the same red already used for mute/critical states throughout
// (Osd.qml, Bluetooth.qml's poweredOff, etc.) -- no new colors
// introduced, just this alert finally drawing from the same well.
//
// BatteryAlertState.qml (services/) owns the UPower trigger logic; this
// file only renders whatever state it currently holds and reports back
// which button was pressed.
//
// Glass: back to the same recipe Osd.qml uses (a two-stop opaque
// Gradient body, lighter top/darker bottom, plus GlassRim's diagonal
// edge highlight) -- dropped in the first pass at this layout (the
// mockup's own card has no rim highlight) and asked back in. Osd.qml's
// own header has the fuller history of why this recipe is "glass" in
// look without being a real compositor blur.
//
// Battery glyph: gone, along with the tile it sat in -- replaced by
// BatteryRing.qml, a thick ring whose own stroke is the gauge, with the
// percentage and a status icon (plug / lightning) scrolling inside it.
// BatteryIcon.qml's small hand-drawn gauge is still what Battery.qml
// draws in the top bar, where it has to read at 20x10px next to a
// number; at 84px on a card it was just a picture of a battery.
//
// Check/X badges: the checkmark is Phosphor Bold's real "check" glyph
// (0xe182, found by rendering the font's own glyph table and reading
// off the shape -- this subset's codepoints are NOT alphabetical
// site-wide the way Battery.qml's battery-* run happens to be, so
// guessing wasn't reliable). No comparably quick find for a plain "x"
// glyph in the time that was worth spending on a small badge, so the X
// is hand-drawn instead -- two thin crossed Rectangles, same
// "build the shape from Rectangles" approach BatteryIcon.qml/
// GlassRim.qml already use elsewhere in this bar.
// HyperOS pass: redesigned as the "C" of the mockups ("chiffre") -- the
// iOS-style card above (ring gauge, title, two outlined buttons with
// coloured check/X badges) gave way to:
//   - the level in large type, in the state colour, with the state glyph
//     beside it;
//   - a full-width gauge under it, straight level edge, same state colour;
//   - the title and one status line (time left, from PowerState's
//     smoothed estimate when it has one);
//   - two capsule buttons on one row: the action in the inverted white of
//     every "on" control in the drawers, the dismissal in plain grey.
// Colour now marks the STATE only (the gauge, the number), never the
// buttons. The card keeps the drawers' convex rim.
Rectangle {
    id: card

    readonly property int percent: BatteryAlertState.percent
    readonly property bool charging: BatteryAlertState.mode === "charging"
    readonly property bool adapterLost: BatteryAlertState.mode === "adapter"

    function mixColor(a, b, t) {
        const k = Math.max(0, Math.min(1, t));
        return Qt.rgba(a.r + (b.r - a.r) * k, a.g + (b.g - a.g) * k, a.b + (b.b - a.b) * k, 1);
    }
    // The state colour: green while charging, amber when the charger just
    // dropped, and on a low battery amber turning red as it falls (amber
    // down to 15%, red from 5%, blended between).
    readonly property color accent: {
        if (card.charging) return DrawerTheme.positive;
        const warm = DrawerTheme.warning;
        if (card.adapterLost) return warm;
        const p = Math.max(0, Math.min(100, card.percent));
        if (p >= 15) return warm;
        return card.mixColor(warm, DrawerTheme.danger, (15 - p) / 10);
    }

    readonly property string statusLine: {
        const s = PowerState.estimateSeconds;
        const mins = Math.round(s / 60);
        const span = mins >= 60 ? Math.floor(mins / 60) + " h " + (mins % 60) + " min" : mins + " min";
        if (card.charging) return s > 60 ? "Full in about " + span : "Plugged in";
        if (card.adapterLost) return "Running on battery";
        return s > 60 ? "About " + span + " left" : "Plug in soon";
    }

    width: 300
    height: content.implicitHeight + 40
    radius: 26
    color: DrawerTheme.panelTop

    layer.enabled: true
    layer.effect: GlassLens { radius: card.radius }

    opacity: BatteryAlertState.alertVisible ? 1 : 0
    scale: BatteryAlertState.alertVisible ? 1 : 0.9
    Behavior on opacity { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
    Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }

    Column {
        id: content
        x: 20
        y: 20
        width: parent.width - 40
        spacing: 14

        // ---- the level, large ------------------------------------------
        Item {
            width: parent.width
            height: number.implicitHeight

            Row {
                id: number
                anchors.left: parent.left
                spacing: 2
                Text {
                    id: digits
                    renderType: Text.NativeRendering
                    font.hintingPreference: Font.PreferNoHinting
                    text: card.percent
                    color: card.charging ? DrawerTheme.primary : card.accent
                    font.family: Fonts.ui
                    font.pixelSize: 48
                    font.weight: Font.DemiBold
                    font.features: { "tnum": 1 }
                }
                Text {
                    anchors.baseline: digits.baseline
                    renderType: Text.NativeRendering
                    font.hintingPreference: Font.PreferNoHinting
                    text: "%"
                    color: digits.color
                    font.family: Fonts.ui
                    font.pixelSize: 22
                    font.weight: Font.Medium
                }
            }

            Text {
                anchors.right: parent.right
                anchors.bottom: number.bottom
                anchors.bottomMargin: 8
                renderType: Text.NativeRendering
                font.hintingPreference: Font.PreferNoHinting
                // mgc flash while charging, battery_1 otherwise.
                text: card.charging ? "" : ""
                color: card.accent
                font.family: Fonts.iconMingcute
                font.pixelSize: 24
            }
        }

        // ---- the gauge -------------------------------------------------
        // A full track-shaped capsule in the state colour, clipped to the
        // level: straight level edge, the left end always following the
        // track's curve (the same construction as Balise's brightness
        // gauge).
        Rectangle {
            id: gauge
            width: parent.width
            height: 14
            radius: height / 2
            color: Qt.rgba(card.accent.r, card.accent.g, card.accent.b, 0.22)

            Item {
                width: parent.width * Math.max(0, Math.min(1, card.percent / 100))
                height: parent.height
                clip: true
                Rectangle {
                    width: gauge.width
                    height: gauge.height
                    radius: gauge.radius
                    color: card.accent
                }
            }
        }

        // ---- title and status ------------------------------------------
        Column {
            width: parent.width
            spacing: 3
            Text {
                renderType: Text.NativeRendering
                font.hintingPreference: Font.PreferNoHinting
                text: card.adapterLost ? "Charger dropped"
                    : (card.charging ? "Charging" : "Battery low")
                color: DrawerTheme.primary
                font.family: Fonts.ui
                font.pixelSize: 17
                font.weight: Font.DemiBold
            }
            Text {
                renderType: Text.NativeRendering
                font.hintingPreference: Font.PreferNoHinting
                text: card.statusLine
                color: DrawerTheme.secondary
                font.family: Fonts.ui
                font.pixelSize: 13
            }
        }

        // ---- the two choices -------------------------------------------
        Row {
            width: parent.width
            spacing: 8

            PillButton {
                width: (parent.width - parent.spacing) / 2
                primary: true
                // mgc wind (balanced) while charging, leaf (power saver)
                // otherwise.
                glyph: card.charging ? "" : ""
                label: card.charging ? "Balanced" : "Power saver"
                onClicked: card.charging
                    ? BatteryAlertState.activateBalancedMode()
                    : BatteryAlertState.activateLowPowerMode()
            }
            PillButton {
                width: (parent.width - parent.spacing) / 2
                label: card.charging || card.adapterLost ? "Dismiss" : "Not now"
                onClicked: BatteryAlertState.dismiss()
            }
        }
    }

    component PillButton: Rectangle {
        id: btn
        property bool primary: false
        property string glyph: ""
        property string label: ""
        signal clicked()

        height: 40
        radius: height / 2
        color: btn.primary
            ? (area.containsMouse ? Qt.rgba(DrawerTheme.on.r, DrawerTheme.on.g, DrawerTheme.on.b, 0.88) : DrawerTheme.on)
            : (area.containsMouse ? DrawerTheme.accentStrongest : DrawerTheme.cardRaised)
        Behavior on color { ColorAnimation { duration: 120 } }

        Row {
            anchors.centerIn: parent
            spacing: 6
            Text {
                visible: btn.glyph !== ""
                anchors.verticalCenter: parent.verticalCenter
                renderType: Text.NativeRendering
                font.hintingPreference: Font.PreferNoHinting
                text: btn.glyph
                color: btn.primary ? DrawerTheme.onInk : DrawerTheme.primary
                font.family: Fonts.iconMingcute
                font.pixelSize: 15
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                renderType: Text.NativeRendering
                font.hintingPreference: Font.PreferNoHinting
                text: btn.label
                color: btn.primary ? DrawerTheme.onInk : DrawerTheme.primary
                font.family: Fonts.ui
                font.pixelSize: 14
                font.weight: Font.DemiBold
            }
        }

        MouseArea {
            id: area
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: btn.clicked()
        }
    }
}
