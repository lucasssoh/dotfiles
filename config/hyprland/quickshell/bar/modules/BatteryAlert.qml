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
Rectangle {
    id: card

    readonly property int percent: BatteryAlertState.percent
    // BatteryAlertState.critical (<= the last tier) is no longer read
    // here: the warmth ramp below is a continuous function of the level,
    // so "is this the critical tier" stopped being a color decision --
    // 5% simply lands on the ramp's hot end. The state still tracks it
    // for the trigger logic.

    // Second mode of this same card: the charger was just plugged in
    // (BatteryAlertState.mode, see that file's "charger plugged in"
    // section). Everything below reads `charging` rather than being a
    // second card -- plugging in while the warning is up is the ANSWER
    // to that warning, so the card answers in place: green accent, the
    // glyph grows its charging '+', headline and both pills re-label.
    // The morph is free, animation-wise: the color properties below are
    // Behavior-animated at the few places that matter, and nothing in
    // the layout moves (same tile, same headline row, same two pills at
    // the same sizes), which is exactly why this fits in one card
    // instead of needing a second surface.
    readonly property bool charging: BatteryAlertState.mode === "charging"

    // Warmth ramp -- the unplugged accent is no longer two fixed colors
    // (platinum, then red below the last tier) but a continuous slide
    // from cool to hot as the level drops (asked for: "accentuer un peu
    // la chaleur de la couleur en fonction du niveau de batterie si ce
    // n'est pas chargé"). Three anchors, linear between them, flat
    // outside:
    //
    //     >= 30%   #a8b4c4  platinum, this bar's neutral accent
    //       15%    #ffb454  amber -- the SAME amber Battery.qml already
    //                       uses for "low, but eco is on"
    //     <= 5%    #ff6e6e  red -- the critical tier, and the same red
    //                       used for mute/critical everywhere else
    //
    // Anchored on the tiers rather than on round numbers: 20/10/5 are
    // where this card actually fires, so a 20% alert opens visibly warm,
    // a 10% one amber, a 5% one fully red -- the color carries the
    // urgency the tier already encodes, instead of the card looking
    // identical at 20% and at 6%.
    //
    // Interpolated in straight RGB, deliberately NOT through hue: a hue
    // sweep from platinum-blue to amber runs through green on the way,
    // and green is this card's OTHER state (charging). Straight RGB
    // passes through a muted tan instead, which reads as "warming up"
    // and can never be mistaken for the charging color.
    //
    // No ramp while charging: green is a state, not a level, and the
    // whole point of the plugged-in card is that the level stopped
    // being the news.
    function mixColor(a, b, t) {
        const k = Math.max(0, Math.min(1, t));
        return Qt.rgba(a.r + (b.r - a.r) * k,
                       a.g + (b.g - a.g) * k,
                       a.b + (b.b - a.b) * k, 1);
    }
    readonly property color warmAccent: {
        const p = Math.max(0, Math.min(100, card.percent));
        const cool = Qt.rgba(0.659, 0.706, 0.769, 1);   // #a8b4c4
        const warm = Qt.rgba(1.0, 0.706, 0.329, 1);     // #ffb454
        const hot = Qt.rgba(1.0, 0.431, 0.431, 1);      // #ff6e6e
        if (p >= 30) return cool;
        if (p <= 5) return hot;
        if (p >= 15) return card.mixColor(cool, warm, (30 - p) / 15);
        return card.mixColor(warm, hot, (15 - p) / 10);
    }

    // NOT `readonly` (unlike every other derived property in this file):
    // a Behavior can only be attached to a writable property -- QML
    // refuses to load with "accentLight is a read-only property"
    // otherwise. The bindings below are still the only thing that ever
    // writes them.
    property color accent: charging ? "#a3d9a5" : card.warmAccent
    property color accentLight: charging ? "#bfe6c0" : Qt.lighter(card.warmAccent, 1.12)
    Behavior on accent { ColorAnimation { duration: 220; easing.type: Easing.OutCubic } }
    Behavior on accentLight { ColorAnimation { duration: 220; easing.type: Easing.OutCubic } }

    // Square, deliberately -- width is the SAME literal as height below
    // (292), not derived from it. The square target is THIS container,
    // the whole card, not whatever icon sits at the top of it (that one
    // is square on its own terms, and was a wrong guess at what "square"
    // meant once already).
    width: 292
    // Sum of the fixed rows below (20 top pad + 84 ring + 12 gap +
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

    // Deliberately NOT `visible: alertVisible`: that was tried and is
    // wrong twice over -- it does not zero an item's width/height in QML
    // (so the window above it stayed 292x292 and kept eating clicks
    // anyway, the actual bug), and it would skip the fade-out below by
    // yanking the card out of the scene on the first frame of a dismiss.
    // The click-through fix lives on the window instead, as an input
    // mask -- see batteryAlertWindow in shell.qml.
    opacity: BatteryAlertState.alertVisible ? 1 : 0
    scale: BatteryAlertState.alertVisible ? 1 : 0.9
    Behavior on opacity { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
    Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }

    // The icon: one thick ring, its stroke doing the gauging, with the
    // percentage and a status glyph inside it (BatteryRing.qml -- see
    // that file for the arc/flow/scroll mechanics). Replaced the
    // rounded-square TILE + small battery glyph this card inherited from
    // the Figma mockup: asked for explicitly ("un simple cercle epaix
    // suffit et la jauge c'est le remplissage du border"), and the tile
    // went with it -- a ring needs no box around it.
    //
    // 84 across at topMargin 20 with a 12 gap under it, where the tile
    // was 76 at 24 with a 16 gap: 20 + 84 + 12 is the same 116 as
    // 24 + 76 + 16, so the card's height literal below still adds up
    // and it stays square. A bigger ring for free, in other words.
    BatteryRing {
        id: gauge
        anchors.top: parent.top
        anchors.topMargin: 20
        anchors.horizontalCenter: parent.horizontalCenter
        width: 84
        height: 84
        percent: card.percent
        charging: card.charging
        // NOT card.accent: that one already resolves charging -> green,
        // and the ring needs both colors at once -- its two center
        // faces (plug / lightning) are both on screen during the scroll.
        lowColor: card.warmAccent
        chargeColor: "#a3d9a5"
    }

    Text {
        id: titleLabel
        anchors.top: gauge.bottom
        anchors.topMargin: 12
        anchors.horizontalCenter: parent.horizontalCenter
        renderType: Text.NativeRendering
        font.hintingPreference: Font.PreferNoHinting
        // No percentage here anymore: the ring above says it, in bigger
        // type, right next to the gauge that means it. This line names
        // the STATE instead -- two words, no number to re-read.
        text: card.charging ? "Charging" : "Battery low"
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
            text: card.charging ? "Balanced mode" : "Power save mode"
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
            onClicked: card.charging
                ? BatteryAlertState.activateBalancedMode()
                : BatteryAlertState.activateLowPowerMode()
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
            // "Not now" postpones a decision; once you're plugged in
            // there's nothing left to postpone, so the same pill says
            // what it now does instead.
            text: card.charging ? "Dismiss" : "Not now"
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
