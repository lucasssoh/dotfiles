import QtQuick
import Quickshell.Services.UPower
import "../theme"
import "../services"

// Native port of waybar's `battery` module. Zero exec, zero poll:
// UPower.displayDevice is DBus-signal-backed. Collapses to nothing on
// desktops with no battery (isLaptopBattery false / not present) --
// same graceful-degradation intent as the old shell one-liner had.
//
// BatteryPreviewState.qml (services/) lets `present`/percentage/
// charging be overridden for a screenshot/preview on a desktop with no
// real battery, WITHOUT touching real UPower state -- see that file's
// own header. Every read below goes through root.present/root.pct/
// root.isCharging rather than root.device directly, so the real device
// and the preview override share one code path instead of two.

Item {
    id: root

    readonly property var device: UPower.displayDevice
    readonly property bool realPresent: device && device.isLaptopBattery && device.ready
    readonly property bool present: BatteryPreviewState.active || realPresent
    readonly property real pct: BatteryPreviewState.active ? BatteryPreviewState.percent : (realPresent ? device.percentage : 0)
    readonly property bool isCharging: BatteryPreviewState.active
        ? BatteryPreviewState.charging
        : (realPresent && device.state === UPowerDeviceState.Charging)

    // Low tier matches BatteryAlertState.tiers[0] (20) -- "below the
    // threshold [that alert fires at]", same line waybar's original
    // #battery rule never drew (that rule stayed plain text always,
    // see the old comment this replaced) but was asked for here
    // specifically: eco (power-saver) active tones it down to amber,
    // NOT eco leaves it red -- the color is carrying "is anything being
    // done about this" as much as "battery is low" on its own. Never
    // fires while charging (isCharging's own green already covers
    // "this is being handled").
    readonly property bool lowBattery: root.present && !root.isCharging && root.pct <= 20
    readonly property bool ecoActive: PowerProfiles.profile === PowerProfile.PowerSaver

    // Lenovo conservation mode: the EC's binary ~60% charge cap (read off
    // sysfs by SystemStats, empty/false on any non-IdeaPad). Same
    // preview-or-real shape as isCharging above.
    readonly property bool conservationActive: BatteryPreviewState.active
        ? BatteryPreviewState.conservation
        : SystemStats.conservationMode

    // "The charger is powering the machine and the battery is at rest" --
    // neither charging nor discharging. Both UPower states that mean it:
    //
    //   FullyCharged   100%, charge terminated (kernel status "Full")
    //   PendingCharge  on AC, charging inhibited (kernel "Not charging")
    //
    // Physically identical -- the power-path controller feeds the system
    // from the adapter and leaves the cell idle -- so they get one icon.
    // Both are needed rather than just FullyCharged: with conservation
    // mode on, the battery NEVER reaches FullyCharged, it parks in
    // PendingCharge at ~60% for as long as the machine stays docked, so
    // keying only off "full" would mean this icon essentially never
    // appears on the one machine it was asked for. It also sidesteps not
    // knowing which of the two a given IdeaPad's EC actually reports at
    // the cap -- that varies by model, and covering both makes it moot.
    readonly property bool atRestOnAC: BatteryPreviewState.active
        ? BatteryPreviewState.atRest
        : (realPresent && (device.state === UPowerDeviceState.FullyCharged
                        || device.state === UPowerDeviceState.PendingCharge))

    // The one state-dependent color set this module has -- charging
    // (light green) and low-without-charging (amber if eco's already
    // on, red otherwise) are both genuine STATE, unlike a fixed
    // charge-level color ramp (25/50/75%, say) which waybar's original
    // rule deliberately never had and this still doesn't.
    //
    // Conservation mode swaps that charging green for sky blue: the cap
    // only MEANS anything while charging -- it's the difference between
    // "climbing to 100" and "climbing to ~60 and stopping" -- so it
    // deliberately doesn't tint the discharging or full states, where it
    // would just be noise. Once the cap is reached UPower leaves the
    // Charging state on its own, isCharging goes false, and the color
    // returns to the normal idle white with no special case needed here.
    // Same lightness as the green it replaces (~74%), so the module's
    // visual weight in the pill doesn't shift; well clear of the
    // theme's desaturated blue-grey accent (#a8b4c4) so it still reads
    // as blue rather than as a greyed-out green.
    readonly property color batteryColor: {
        if (root.isCharging) return root.conservationActive ? "#8ecae6" : "#a3d9a5";
        if (root.lowBattery) return root.ecoActive ? "#ffb454" : "#ff6e6e";
        return "#f2f2f7";
    }

    // The REAL culprit behind "too much space" at every value, including
    // the widest (100) -- this Item centered content inside a padded,
    // floored box (+20, min 64) meant for METRICS' own square-ish stat
    // pills, a leftover from when Battery lived there. Now sitting among
    // TOOLS' tighter icon-only modules instead, it should hug its own
    // content just as tightly as those do -- no floor, minimal padding.
    implicitWidth: label.implicitWidth + 2
    implicitHeight: 24
    visible: root.present

    // Quiet acknowledgement that the charger was just plugged in.
    // BatteryAlertState only puts its centered card on screen when
    // the plug-in actually answers something (a low-battery warning
    // on screen, or a still-low battery) -- but the EVENT is worth a
    // signal at any level, so it emits `plugged()` every time and
    // this module pops once. One scale bump on the whole
    // number+icon row, no color of its own: batteryColor above
    // already swings to green on the same UPower state change, so
    // the pulse is just what makes you notice it happen.
    Connections {
        target: BatteryAlertState
        function onPlugged() { plugPulse.restart(); }
    }
    SequentialAnimation {
        id: plugPulse
        NumberAnimation { target: label; property: "scale"; to: 1.22; duration: 130; easing.type: Easing.OutCubic }
        NumberAnimation { target: label; property: "scale"; to: 1.0; duration: 380; easing.type: Easing.OutBack }
    }

    Row {
        id: label
        anchors.centerIn: parent
        // 6 -> 4, matching Cpu.qml/Memory.qml/Temperature.qml/Fan.qml's
        // own icon-text spacing in this same pill (asked for: "réduit le
        // gap").
        spacing: 4
        visible: root.present

        // No "%" unit (asked for: "beaucoup plus sobre et économe") --
        // the battery icon right next to it already says "this is a
        // percentage", same reasoning Cpu.qml/Memory.qml's own bare
        // numbers already use elsewhere in this pill.
        //
        // Fixed width (asked for: "l'espace pour battery soit fixe") --
        // this Text's own `width` is pinned to pctRef's implicitWidth
        // (a hidden "100" reference, always the widest this ever
        // renders) instead of following its own live content. Without
        // this, 1/10/100 each measure a different implicitWidth, so the
        // module's own width (and everything to its right in this pill
        // -- Clock, the power dot) shifted by a few px on every
        // percentage change.
        //
        // BEFORE the icon, right-aligned within that fixed slot --
        // corrected after a first, wrong guess at this (icon-then-
        // number, left-aligned): asked for explicitly, "à gauche de
        // l'icon et aligné à droite". Right-aligned here puts the digit
        // flush against the icon regardless of its own width, with any
        // leftover slack pushed out to the far left of the whole
        // cluster instead -- the least noticeable place for it, further
        // from everything else in this pill than a gap right next to
        // the icon would be.
        Text {
            renderType: Text.NativeRendering
            font.hintingPreference: Font.PreferNoHinting
            text: root.present ? Math.round(root.pct) : ""
            color: root.batteryColor
            font.family: Fonts.ui
            font.pixelSize: 13
            width: pctRef.implicitWidth
            horizontalAlignment: Text.AlignRight
        }
        Text {
            id: pctRef
            visible: false
            text: "100"
            font.family: Fonts.ui
            font.pixelSize: 13
        }

        // Custom-drawn proportional gauge (BatteryIcon.qml), not a
        // Phosphor font glyph -- asked for after a reference screenshot
        // of iOS's own battery widget. Replaced the previous 5-tier
        // Nerd Font icon() lookup entirely; UPower's own percentage
        // drives the fill directly now, no tier bucketing needed.
        BatteryIcon {
            // Hidden, not merely covered, when the plug replaces it: a
            // QtQuick positioner (this Row) drops invisible children from
            // its layout entirely, so the two icons never both reserve
            // space.
            visible: !root.atRestOnAC
            anchors.verticalCenter: parent.verticalCenter
            width: 20
            height: 10
            percent: root.present ? root.pct : 100
            charging: root.isCharging
            outlineColor: root.batteryColor
            fillColor: root.batteryColor
        }

        // ph-plugs-connected (U+EB56) -- two mated plugs, i.e. "running
        // off the mains", rather than ph-plug's (U+E946) lone wall pin.
        //
        // Written as a \u escape, not a literal PUA character: the
        // codepoint was first taken from the font's GSUB ligature table
        // (mapping the icon NAME "plugs-connected" to its glyph) and that
        // reconstruction put it at U+EB5A, which is a different icon
        // entirely -- caught only by rendering the candidates and looking
        // at them. An escape keeps the intended codepoint readable in the
        // source instead of hiding it inside an invisible glyph, so the
        // next such mistake is visible in a diff.
        //
        // A gauge is
        // the wrong picture for this state: the cell is idle and its
        // level says nothing about what's powering the machine. The
        // PERCENTAGE stays, and carries the part that still matters --
        // how much you'd actually have if you unplugged, which under a
        // ~60% cap is not the "100" a plug icon would otherwise imply.
        //
        // Pinned to BatteryIcon's own 20px rather than left to the
        // glyph's advance width, so swapping between the two doesn't
        // shift this module's width (and with it everything to its right
        // in the pill) every time the charger goes in or out -- the same
        // reasoning as the fixed percentage slot above, applied to a
        // state change instead of a value change.
        Text {
            visible: root.atRestOnAC
            anchors.verticalCenter: parent.verticalCenter
            text: "\uEB56"
            color: root.batteryColor
            font.family: Fonts.iconPhosphorBold
            font.pixelSize: 15
            width: 20
            horizontalAlignment: Text.AlignHCenter
        }
    }
}
