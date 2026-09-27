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

    // The ink ramp this module draws with. Points at the dark-material
    // singleton by default, which is what every call site below used
    // directly before this property existed -- so this changes nothing on
    // its own. It exists so the band's islands can hand a LIGHT ramp to
    // the modules sitting on them, per island, without touching any of
    // those call sites again. See theme/Ink.qml's MATERIAL note for why
    // the material flips rather than the ink alone.
    property QtObject ink: Ink

    // Which bar instance this module belongs to, handed down by shell.qml
    // exactly as BaliseButton/NotificationBell take theirs -- the power
    // drawer opens on the monitor whose bar was clicked. Null on any
    // caller that doesn't set it, which simply means the drawer opens on
    // no particular screen rather than crashing.
    property var screen: null

    readonly property var device: UPower.displayDevice
    readonly property bool realPresent: device && device.isLaptopBattery && device.ready
    readonly property bool present: BatteryPreviewState.active || realPresent
    // *100: UPowerDevice.percentage is a 0..1 double, NOT an already-
    // scaled 0-100 percentage -- the same trap Network.qml's
    // signalStrength and BaliseButton.qml before it both fell into, and
    // the same fix. Everything downstream of root.pct is on the 0-100
    // scale: lowBattery's `<= 20` below, BatteryIcon's own `percent`
    // (documented "0-100", divided by 100 internally), and the
    // Math.round() that draws the number -- so without this a real 49%
    // battery arrives as 0.49, rounds to 0, and the module renders a
    // flat "0" over an empty gauge.
    //
    // Never caught before because no machine in this repo had a battery
    // that enumerates: the desktop and the TUF both have no BAT*, so
    // realPresent was false everywhere and this branch had literally
    // never been evaluated. Every previous check of this module went
    // through BatteryPreviewState instead, whose `percent` is clamped to
    // 0-100 by its own set() -- the preview path was right and the real
    // path was wrong, which is exactly why the preview never showed it.
    readonly property real pct: BatteryPreviewState.active ? BatteryPreviewState.percent : (realPresent ? device.percentage * 100 : 0)
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
        if (root.isCharging) return root.conservationActive ? "#8ecae6" : root.ink.positive;
        if (root.lowBattery) return root.ecoActive ? "#ffb454" : root.ink.danger;
        return root.ink.primary;
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

    // Percentage, then gauge, then (on AC only) the mains badge. The
    // percentage sat inside the pill for part of the HyperOS pass and is
    // back beside it -- see the slot below and BatteryPill.qml.
    //
    // The one thing that still changes this module's width is the mains
    // badge after the gauge: a MingCute bolt while charging, the Lucide plug
    // while the cell is at rest on AC (MingCute has no plug glyph). It
    // appears and disappears only when the charger goes in or out, never
    // with the percentage, which is the rule the old fixed slot existed
    // to keep.
    Row {
        id: label
        anchors.centerIn: parent
        spacing: 4
        visible: root.present

        // The percentage, left of the gauge, in a fixed slot: pinned to
        // pctRef's width (a hidden "100", the widest it can read) and
        // right-aligned, so 1/10/100 never shift the row and the digits
        // sit flush against the gauge. Same single text style as the rest
        // of the band (13px Medium) and its plain primary ink -- the state colour
        // (charging green, low red...) stays on the gauge alone (asked for).
        Text {
            anchors.verticalCenter: parent.verticalCenter
            renderType: Text.NativeRendering
            font.hintingPreference: Font.PreferNoHinting
            text: root.present ? Math.round(root.pct) : ""
            color: root.ink.primary
            font.family: Fonts.ui
            font.pixelSize: 13
            font.weight: Font.Medium
            font.features: { "tnum": 1 }
            width: pctRef.implicitWidth
            horizontalAlignment: Text.AlignRight
        }
        Text {
            id: pctRef
            visible: false
            text: "100"
            font.family: Fonts.ui
            font.pixelSize: 13
            font.weight: Font.Medium
            font.features: { "tnum": 1 }
        }

        BatteryPill {
            anchors.verticalCenter: parent.verticalCenter
            percent: root.present ? root.pct : 100
            color: root.batteryColor
            // Where conservation mode will stop the charge -- shown only
            // while the machine is on AC, where it answers "how far will
            // this go". On battery the cap is irrelevant and the tick
            // would just be noise.
            capAt: root.conservationActive && (root.isCharging || root.atRestOnAC) ? 60 : -1
        }

        Text {
            visible: root.isCharging || root.atRestOnAC
            anchors.verticalCenter: parent.verticalCenter
            renderType: Text.NativeRendering
            font.hintingPreference: Font.PreferNoHinting
            // mgc flash_fill while charging; lu-plug (the glyph this
            // module already used for "at rest on AC") otherwise.
            text: root.isCharging ? "\uEE06" : "\uE45C"
            color: root.batteryColor
            font.family: root.isCharging ? Fonts.iconMingcute : Fonts.iconPhosphorBold
            font.pixelSize: 14
        }
    }

    // This module IS the affordance for the power drawer (modules/power/
    // PowerHome.qml): the battery readout is the thing whose detail the
    // drawer shows, so clicking it is where a user looks first -- and it
    // costs the TOOLS pill no extra width, which a dedicated button
    // beside it would have. Same togglePanel(screen) contract Balise and
    // the notification center are opened with.
    //
    // Last child on purpose: a MouseArea only receives what is not taken
    // above it, and declaring it after the Row above means nothing in
    // that Row can shadow it.
    MouseArea {
        id: hit
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: PowerState.togglePanel(root.screen)
    }
}
