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
// Battery glyph: BatteryIcon.qml's hand-drawn proportional gauge (outline
// + nub + exact-percentage fill), reused verbatim from the pass before
// this one -- still correct here, just recolored and set inside a tile
// instead of sitting bare on the card.
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
Rectangle {
    id: card

    readonly property int percent: BatteryAlertState.percent
    readonly property bool critical: BatteryAlertState.critical
    readonly property color accent: critical ? "#ff6e6e" : "#a8b4c4"
    readonly property color accentLight: critical ? "#ff8a8a" : "#c3ccd8"

    // Square, deliberately -- width is the SAME literal as height below
    // (292), not derived from it, same "two equal literals" approach
    // iconTile already uses. The square target is THIS container, the
    // whole card -- not iconTile (already square on its own terms) and
    // not the battery glyph inside it (reverted back to its normal
    // elongated shape above after a wrong guess at squaring that
    // instead).
    width: 292
    // Sum of the fixed rows below (24 top pad + 76 icon tile + 16 gap +
    // 22 title + 22 gap + 50 button + 10 gap + 50 button + 22 bottom
    // pad) -- no QtQuick.Layouts in this codebase, so the height is
    // this literal total rather than something a Column would compute
    // for us.
    height: 292
    radius: 24

    // Narrower and darker than the first pass (top stop #3f4450 ->
    // #1e2128, bottom left alone) -- asked for ("réduire le spectre",
    // "plus sombre"): less top-to-bottom range AND a darker card
    // overall, not just a flatter one.
    gradient: Gradient {
        GradientStop { position: 0.0; color: "#ff1e2128" }
        GradientStop { position: 1.0; color: "#ff060608" }
    }

    GlassRim { cornerRadius: card.radius }
    GlassRim { cornerRadius: card.radius; lightOrigin: "bottomRight"; strength: 0.45 }

    opacity: BatteryAlertState.alertVisible ? 1 : 0
    scale: BatteryAlertState.alertVisible ? 1 : 0.9
    Behavior on opacity { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
    Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }

    // Square, deliberately -- width/height are the same literal (76),
    // not derived from each other, so this can never drift into a
    // rectangle as the rest of the layout changes around it. Bigger
    // than the first pass (64 -> 76) specifically to give the icon
    // inside more breathing room: BatteryIcon itself stayed the same
    // size, so the padding around it grew on its own.
    Rectangle {
        id: iconTile
        anchors.top: parent.top
        anchors.topMargin: 24
        anchors.horizontalCenter: parent.horizontalCenter
        width: 76
        height: 76
        radius: 18
        color: "#1a1d2a"

        // Back to BatteryIcon's normal elongated proportions -- the
        // square target was never this icon, it was the CARD as a
        // whole (see card.width/height below). Squaring the icon itself
        // was the wrong fix, corrected here.
        BatteryIcon {
            anchors.centerIn: parent
            width: 34
            height: 17
            percent: card.percent
            outlineColor: card.accent
            fillColor: card.accent
            outlineOpacity: 1.0
        }
    }

    Text {
        id: titleLabel
        anchors.top: iconTile.bottom
        anchors.topMargin: 16
        anchors.horizontalCenter: parent.horizontalCenter
        renderType: Text.NativeRendering
        font.hintingPreference: Font.PreferNoHinting
        text: card.percent + "% battery remaining"
        color: "#f2f2f7"
        font.family: Fonts.ui
        font.pixelSize: 17
        font.bold: true
    }

    // No separate description line -- removed (asked for): it only
    // ever repeated what "Power save mode" below already says, once
    // that button stopped being the generic "Activate mode".
    //
    // Real action, not decoration -- switches power-profiles-daemon to
    // power-saver (see BatteryAlertState.activateLowPowerMode).
    Rectangle {
        id: primaryButton
        anchors.top: titleLabel.bottom
        anchors.topMargin: 22
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: 20
        anchors.rightMargin: 20
        height: 50
        radius: height / 2
        // Exactly secondaryButton's own style (asked for explicitly:
        // "prend exactement le style de not now") -- transparent at
        // rest, a constant thin border regardless of hover, and the
        // SAME #14161d dark hover fill, no tint of its own. A green
        // tint was tried here first (asked for at the time) and then
        // asked back out again once it was compared side-by-side with
        // secondaryButton's own plain #14161d -- the two pills are
        // meant to look like one shared style now, not a matched pair
        // with one recolored.
        color: primaryArea.containsMouse ? "#14161d" : "transparent"
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.18)
        Behavior on color { ColorAnimation { duration: 120 } }

        Text {
            anchors.left: parent.left
            anchors.leftMargin: 18
            anchors.verticalCenter: parent.verticalCenter
            renderType: Text.NativeRendering
            font.hintingPreference: Font.PreferNoHinting
            text: "Power save mode"
            color: "#ffffff"
            font.family: Fonts.ui
            font.pixelSize: 15
            font.bold: true
        }

        // No fill (asked for, same as the pills themselves) -- a thin
        // accent-colored ring instead of a solid disc, with the
        // checkmark glyph tinted to match rather than staying white
        // (white only made sense against a solid fill).
        Rectangle {
            id: checkBadge
            anchors.right: parent.right
            anchors.rightMargin: 7
            anchors.verticalCenter: parent.verticalCenter
            width: 36
            height: 36
            radius: 18
            color: "transparent"
            border.width: 1.5
            border.color: card.accentLight

            Text {
                anchors.centerIn: parent
                renderType: Text.NativeRendering
                font.hintingPreference: Font.PreferNoHinting
                text: ""
                color: card.accentLight
                font.family: Fonts.iconPhosphorBold
                font.pixelSize: 16
            }
        }

        MouseArea {
            id: primaryArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: BatteryAlertState.activateLowPowerMode()
        }
    }

    Rectangle {
        id: secondaryButton
        anchors.top: primaryButton.bottom
        anchors.topMargin: 10
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: 20
        anchors.rightMargin: 20
        height: 50
        radius: height / 2
        color: secondaryArea.containsMouse ? "#14161d" : "transparent"
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.18)
        Behavior on color { ColorAnimation { duration: 120 } }

        Text {
            anchors.left: parent.left
            anchors.leftMargin: 18
            anchors.verticalCenter: parent.verticalCenter
            renderType: Text.NativeRendering
            font.hintingPreference: Font.PreferNoHinting
            text: "Not now"
            color: "#f2f2f7"
            font.family: Fonts.ui
            font.pixelSize: 15
        }

        // No fill (asked for, same as checkBadge above) -- a thin red
        // ring instead of a solid disc.
        Rectangle {
            anchors.right: parent.right
            anchors.rightMargin: 7
            anchors.verticalCenter: parent.verticalCenter
            width: 36
            height: 36
            radius: 18
            color: "transparent"
            border.width: 1.5
            border.color: "#ff6e6e"

            // Hand-drawn X -- see file header for why (no quick, reliable
            // Phosphor codepoint find for this subset's plain "x" glyph).
            // Two thin bars crossed at +-45deg, both centered on the
            // badge's own center.
            Rectangle {
                anchors.centerIn: parent
                width: 14
                height: 2
                radius: 1
                color: "#ff6e6e"
                rotation: 45
            }
            Rectangle {
                anchors.centerIn: parent
                width: 14
                height: 2
                radius: 1
                color: "#ff6e6e"
                rotation: -45
            }
        }

        MouseArea {
            id: secondaryArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: BatteryAlertState.dismiss()
        }
    }
}
