import QtQuick
import Quickshell.Services.UPower
import ".."          // DrawerHandle / DrawerTile / DrawerGroupLabel
import "../balise"   // BaliseSegmented / RevealPop
import "../../theme"
import "../../services"

// Third drawer entry on toolsIsland, after NotificationCenter and
// BaliseHome -- opened by clicking the Battery module in the TOOLS pill
// (shell.qml), which is the same "click the thing you want the detail of"
// affordance BaliseButton and NotificationBell already are, with the
// difference that it needs no new pixel in the row.
//
// Satisfies the same DrawerIsland contract those two do: `drawerOpen`
// bound from outside, `implicitHeight` computed here, and a
// `Behavior on height` kept equal to the island's own `revealDuration`
// (220) so the content fade does not start mid-stretch. Width is NOT set
// here -- DrawerIsland forces every entry to the island's own
// `fixedDrawerWidth` (360), so everything below sizes off `parent.width`.
//
// What it holds, and why each piece is here:
//
//   * the time remaining, as the headline. It is the one number anyone
//     opens a battery panel to read, so it is the one drawn largest --
//     the level, which the bar already shows at a glance, is demoted to
//     the line underneath.
//   * the charge cap, MOVED out of BaliseHome's tile grid. It was the one
//     control in that drawer that is about the battery rather than about
//     connectivity, and it sat there only because the Airplane tile had
//     freed the slot. Balise's Ethernet tile went back to full width.
//   * the power profile, which was previously reachable only by launching
//     the external `roue` wheel from the Performance module. That still
//     works and is untouched; this is the in-place version for when the
//     drawer is already open.
//   * the history chart. See PowerState.qml for why no sampler was added
//     for it, and PowerCurve.qml for why it plots percent rather than the
//     watts it first plotted.
Item {
    id: root

    property bool drawerOpen: false

    implicitHeight: handle.implicitHeight + 20 + content.implicitHeight + 20
    // Kept equal to DrawerIsland's `revealDuration` -- see the comment
    // there; the island waits out exactly this long before fading content
    // in.
    Behavior on height { NumberAnimation { duration: 220; easing.type: Easing.InOutCubic } }

    // The entrance cascade is driven by a global generation counter, and
    // this drawer's content is built ONCE (unlike Balise's pages, which
    // are rebuilt by a Loader on every navigation) -- so without this kick
    // the cascade would play at bar startup, invisibly, and never again.
    // Same call BaliseHome makes for its own already-on-the-right-page
    // case; harmless that it is global, since only one of the three
    // drawers can be open at a time anyway.
    onDrawerOpenChanged: {
        if (root.drawerOpen) BaliseReveal.replay();
    }

    // ---- conservation mode ------------------------------------------
    //
    // Lifted verbatim from BaliseHome.qml, preview override included: the
    // knob is an IdeaPad-only sysfs attribute (see SystemStats.qml), so on
    // any other machine the tile is not drawn rather than drawn dead.
    readonly property bool conservationAvailable: BatteryPreviewState.active
        ? BatteryPreviewState.conservationAvailable
        : SystemStats.conservationPath !== ""
    readonly property bool conservationOn: BatteryPreviewState.active
        ? BatteryPreviewState.conservation
        : SystemStats.conservationMode

    function setConservation(on) {
        if (BatteryPreviewState.active) {
            BatteryPreviewState.setConservation(on);
            return;
        }
        SystemStats.setConservation(on);
    }

    // ---- power profile ----------------------------------------------
    //
    // Cycles eco -> balanced -> performance. A three-state cycle rather
    // than a segmented picker because this is a Tile like the one beside
    // it, and the pair reads as two controls of the same kind; the
    // wheel (Performance.qml's own click action) is still there for
    // picking one directly.
    function cycleProfile() {
        if (PowerProfiles.profile === PowerProfile.PowerSaver) {
            PowerProfiles.profile = PowerProfile.Balanced;
        } else if (PowerProfiles.profile === PowerProfile.Balanced) {
            PowerProfiles.profile = PowerProfile.Performance;
        } else {
            PowerProfiles.profile = PowerProfile.PowerSaver;
        }
    }

    function profileLabel(p) {
        if (p === PowerProfile.Performance) return "Performance";
        if (p === PowerProfile.PowerSaver) return "Eco";
        return "Balanced";
    }
    // Same three codepoints Performance.qml maps, so the bar glyph and
    // the tile glyph are never two different pictures of one setting.
    function profileGlyph(p) {
        if (p === PowerProfile.Performance) return "";   // lu-zap
        if (p === PowerProfile.PowerSaver) return "";    // lu-leaf
        return "";                                       // lu-wind
    }

    // ---- headline ----------------------------------------------------

    readonly property bool atRest: PowerState.present
        && !PowerState.charging && !PowerState.discharging

    // { h, m } or null when there is nothing to count toward -- parked on
    // the mains, or before the first history has arrived. Split into two
    // numbers rather than formatted into one string because the unit
    // suffixes are drawn smaller than the digits, which needs them as
    // separate Texts.
    readonly property var estParts: {
        const s = PowerState.estimateSeconds;
        if (s <= 0) return null;
        let h = Math.floor(s / 3600);
        let m = Math.round((s % 3600) / 60);
        // Rounding 59.6 minutes up lands on 60, which would render
        // "3 h 60 min".
        if (m === 60) { h += 1; m = 0; }
        return { h: h, m: m };
    }

    readonly property string headlineCaption: {
        if (!PowerState.present) return "—";
        const level = Math.round(PowerState.pct) + "% charged";
        if (root.estParts === null)
            return (root.atRest ? "On AC" : "Estimating") + "  |  " + level;
        return (PowerState.charging ? "Until full" : "Time left") + "  |  " + level;
    }

    // Plain decimal point. This used to force a comma, on the grounds
    // that everything else in the drawer was written in French -- that
    // premise is gone (the rest of this bar, Balise included, labels in
    // English), so the justification went with it.
    function fmtWatts(w) {
        return w.toFixed(1) + " W";
    }

    DrawerHandle {
        id: handle
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        onCloseRequested: PowerState.close()
    }

    Column {
        id: content
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: handle.bottom
        anchors.leftMargin: 20
        anchors.rightMargin: 20
        // 20, the same as BaliseHome's own page area -- no special case
        // needed here. The headline used to sit 5px under the handle
        // against Balise's 31, but this margin was never the cause: see
        // bigDuration below, whose Texts were anchored to the Row's own
        // baseline and so drew their ink above the box entirely. With
        // that fixed this measures 36px, five MORE than Balise, which is
        // the right amount of air under a 28px display number.
        anchors.topMargin: 20
        spacing: 16

        // ---- headline: time left, level, live draw ------------------
        Item {
            id: headline
            width: parent.width
            height: bigRow.height + 3 + subRow.height

            RevealPop { item: headline; index: 0 }

            Item {
                id: bigRow
                width: parent.width
                // 38, not 34: a 28px line box measures ~37, so the old
                // value made the Row overflow its own container and the
                // headline sat proud of the box it was centred in.
                height: 38

                // Digits large, units small beside them -- the shape a
                // phone's battery screen uses, and the reason is that
                // "5 h 15 min" at one size reads as five separate tokens
                // while this reads as one duration.
                // The small unit suffixes align on the BIG digits'
                // baseline, by id -- never on `parent.baseline`.
                //
                // That was the original spelling and it is a trap: the
                // parent here is the Row, a positioner whose own baseline
                // is its top edge, so every Text got pinned by its
                // baseline to y=0 and drew its entire ink ABOVE the box.
                // Measured, the headline started 15px below the panel top
                // where the layout said 38 -- which is the whole of the
                // "collé au top" this fixes. The digits themselves take
                // no vertical anchor at all: left alone they sit at y=0
                // and give the Row its height.
                Row {
                    id: bigDuration
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 3
                    visible: root.estParts !== null

                    Text {
                        id: hoursDigits
                        renderType: Text.NativeRendering
                        font.hintingPreference: Font.PreferNoHinting
                        text: root.estParts ? root.estParts.h : ""
                        color: Ink.primary
                        font.family: Fonts.ui
                        font.pixelSize: 28
                        font.bold: true
                    }
                    Text {
                        anchors.baseline: hoursDigits.baseline
                        renderType: Text.NativeRendering
                        font.hintingPreference: Font.PreferNoHinting
                        text: "h"
                        color: Ink.secondary
                        font.family: Fonts.ui
                        font.pixelSize: 12
                        rightPadding: 4
                    }
                    Text {
                        renderType: Text.NativeRendering
                        font.hintingPreference: Font.PreferNoHinting
                        // Zero-padded: the minutes are the second half of
                        // one number, and "5 h 7 min" reads as a typo.
                        text: root.estParts
                            ? (root.estParts.m < 10 ? "0" + root.estParts.m : root.estParts.m)
                            : ""
                        color: Ink.primary
                        font.family: Fonts.ui
                        font.pixelSize: 28
                        font.bold: true
                    }
                    Text {
                        anchors.baseline: hoursDigits.baseline
                        renderType: Text.NativeRendering
                        font.hintingPreference: Font.PreferNoHinting
                        text: "min"
                        color: Ink.secondary
                        font.family: Fonts.ui
                        font.pixelSize: 12
                    }
                }

                // Nothing to count toward: the level takes the headline
                // slot instead of leaving it blank.
                Row {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 3
                    visible: root.estParts === null

                    Text {
                        id: levelDigits
                        renderType: Text.NativeRendering
                        font.hintingPreference: Font.PreferNoHinting
                        text: PowerState.present ? Math.round(PowerState.pct) : "—"
                        color: Ink.primary
                        font.family: Fonts.ui
                        font.pixelSize: 28
                        font.bold: true
                    }
                    Text {
                        anchors.baseline: levelDigits.baseline
                        renderType: Text.NativeRendering
                        font.hintingPreference: Font.PreferNoHinting
                        text: "%"
                        color: Ink.secondary
                        font.family: Fonts.ui
                        font.pixelSize: 12
                    }
                }
            }

            Item {
                id: subRow
                width: parent.width
                height: 15
                anchors.top: bigRow.bottom
                anchors.topMargin: 3

                Text {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    renderType: Text.NativeRendering
                    font.hintingPreference: Font.PreferNoHinting
                    text: root.headlineCaption
                    color: Ink.secondary
                    font.family: Fonts.ui
                    font.pixelSize: 11
                }

                // The instantaneous draw, and BESIDE IT the median the
                // headline above is actually divided by.
                //
                // Both, not just the first: shown alone, a live "6,9 W"
                // under "18 h 28" reads as a contradiction -- 46Wh at
                // 6.9W is under 7 hours, and nothing on screen explains
                // where the other eleven came from. Printing the median
                // next to it is what makes the headline legible instead
                // of wrong-looking: one number is what the machine is
                // doing this second (and is meant to jump around), the
                // other is what the last quarter of an hour actually
                // cost. See PowerState.medianWatts.
                Text {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    visible: PowerState.present && !root.atRest
                    renderType: Text.NativeRendering
                    font.hintingPreference: Font.PreferNoHinting
                    text: PowerState.medianWatts > 0
                        ? root.fmtWatts(PowerState.watts) + "  ·  med. " + root.fmtWatts(PowerState.medianWatts)
                        : root.fmtWatts(PowerState.watts)
                    color: Ink.secondary
                    font.family: Fonts.ui
                    font.pixelSize: 11
                }
            }
        }

        // ---- the two controls ----------------------------------------
        Row {
            id: tileRow
            width: parent.width
            height: 92
            spacing: 16

            // A positioner reclaims a hidden child's space, it does not
            // stretch the survivor into it -- so the survivor has to be
            // told, the same explicit-width idiom BaliseHome's own rows
            // use.
            DrawerTile {
                visible: root.conservationAvailable
                width: (tileRow.width - 16) / 2
                height: parent.height
                title: "Charge limit"
                revealIndex: 1
                status: root.conservationOn ? "60%" : "Off"
                glyph: ""   // lu-battery-medium
                active: root.conservationOn
                onActivated: root.setConservation(!root.conservationOn)
            }

            DrawerTile {
                visible: PowerProfiles.hasPerformanceProfile
                width: root.conservationAvailable ? (tileRow.width - 16) / 2 : tileRow.width
                height: parent.height
                title: "Profile"
                revealIndex: 2
                status: root.profileLabel(PowerProfiles.profile)
                glyph: root.profileGlyph(PowerProfiles.profile)
                // Balanced is the resting state, so lighting the tile up
                // for it would leave it permanently on and say nothing.
                // Only the two deliberate choices read as active.
                active: PowerProfiles.profile !== PowerProfile.Balanced
                onActivated: root.cycleProfile()
            }
        }

        // ---- the chart -----------------------------------------------
        Column {
            width: parent.width
            spacing: 8

            Item {
                id: chartHeader
                width: parent.width
                height: 24

                DrawerGroupLabel {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: "HISTORY"
                    revealIndex: 3
                }

                // The generic segmented control, which happens to live
                // under balise/ because that is where it was first needed
                // (the EAP method picker). Its own `width` binds to
                // parent.width; overriding it at the call site is what
                // keeps it a compact header control instead of a
                // full-width form row.
                BaliseSegmented {
                    id: spanPicker
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    width: 152
                    height: 24
                    options: PowerState.spanOptions
                    value: String(PowerState.spanSeconds)
                    onPicked: (v) => PowerState.setSpan(parseInt(v))
                }
            }

            // What the two colours mean. Needed because the line changes
            // colour mid-curve and nothing else on screen says why -- a
            // green spike is not self-explanatory until you are told it
            // is the charger.
            Row {
                id: legend
                width: parent.width
                height: 12
                spacing: 14

                RevealPop { item: legend; index: 4; fromScale: 1.0 }

                Row {
                    spacing: 5
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 6; height: 6; radius: 3
                        color: curve.dischargeColor
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        renderType: Text.NativeRendering
                        font.hintingPreference: Font.PreferNoHinting
                        text: "Discharging"
                        color: Ink.secondary
                        font.family: Fonts.ui
                        font.pixelSize: 10
                    }
                }
                Row {
                    spacing: 5
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 6; height: 6; radius: 3
                        color: curve.chargeColor
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        renderType: Text.NativeRendering
                        font.hintingPreference: Font.PreferNoHinting
                        text: "Charging"
                        color: Ink.secondary
                        font.family: Fonts.ui
                        font.pixelSize: 10
                    }
                }
            }

            Item {
                id: curveBlock
                width: parent.width
                height: curve.implicitHeight

                RevealPop { item: curveBlock; index: 5 }

                PowerCurve {
                    id: curve
                    anchors.fill: parent
                    samples: PowerState.samples
                    axisStart: PowerState.axisStart
                    axisEnd: PowerState.axisEnd
                    gapSeconds: PowerState.gapSeconds
                }
            }
        }
    }
}
