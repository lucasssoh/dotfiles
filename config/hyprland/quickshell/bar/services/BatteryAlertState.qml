pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower

// State + trigger logic for the low-battery alert (BatteryAlert.qml
// renders it, one instance per screen via shell.qml's Variants). A
// SEPARATE surface from OsdState.qml's volume/mic/brightness popup, on
// purpose -- see BatteryAlert.qml's header for why a warning gets a
// centered, click-to-dismiss modal instead of a corner popup that times
// out on its own.
//
// Threshold-crossing edge trigger, same reasoning as brightness having
// to be poked rather than watched continuously would run into for
// battery too, just for a different reason: percentage IS pushed live
// here (UPower, zero poll), but firing on every percentageChanged would
// mean a fresh alert every minute or so for the whole last fifth of the
// charge. Instead this watches for the level crossing DOWN through one
// of `tiers` and fires once per crossing, like a low-fuel light rather
// than a fuel gauge. `armedTier` tracks the next still-armed (unfired)
// tier; charging back up past the top tier (+5% hysteresis so a wobble
// right at the boundary doesn't immediately re-disarm/rearm) resets it,
// so the same tiers can warn again on the next discharge.
Singleton {
    id: root

    property bool alertVisible: false
    property int percent: 100
    property bool critical: false   // ≤ the last (most urgent) tier

    // Same startup guard as OsdState.ready -- UPower.displayDevice takes
    // a moment to connect, and that null -> real transition shouldn't be
    // read as a real percentage crossing.
    property bool ready: false
    Timer { interval: 600; running: true; onTriggered: root.ready = true }

    readonly property var battDevice: UPower.displayDevice
    readonly property bool battPresent: root.battDevice && root.battDevice.isLaptopBattery && root.battDevice.ready
    readonly property bool battDischarging: root.battPresent && root.battDevice.state === UPowerDeviceState.Discharging
    readonly property int battPercent: root.battPresent ? Math.round(root.battDevice.percentage) : 100

    readonly property bool battPlugged: root.battPresent
        && (root.battDevice.state === UPowerDeviceState.Charging
            || root.battDevice.state === UPowerDeviceState.FullyCharged
            || root.battDevice.state === UPowerDeviceState.PendingCharge)

    readonly property var tiers: [20, 10, 5]   // last tier = critical
    property int armedTier: 0

    // ---- charger plugged in ----
    //
    // Which of the two things BatteryAlert.qml draws: the low-battery
    // WARNING ("low") or the charger-connected CONFIRMATION ("charging").
    // One surface, two modes, on purpose -- plugging in while the
    // warning is up is the direct ANSWER to that warning, so it belongs
    // in the same card, morphing in place (accent goes green, the glyph
    // grows its charging '+', the headline and both pills re-label)
    // rather than stacking a second popup on top of the first.
    property string mode: "low"   // "low" | "charging"

    // Emitted on every discharging -> plugged edge, whether or not a
    // card is shown for it. The card only appears when it has something
    // to say (see plugIn below); this signal is the always-on one --
    // Battery.qml's own top-bar module listens for it and pulses, so a
    // plug-in at 80% still gets an acknowledgement, just a quiet one.
    signal plugged()

    // Edge, not level: UPower pushes the state change, and only the
    // false -> true transition is a "the charger was just connected"
    // event. The reverse edge matters too, but only for the card that
    // this mode put on screen -- unplugging while "charging" is up
    // makes that card a lie, so it goes away immediately instead of
    // waiting out its own timer.
    onBattPluggedChanged: {
        if (!root.ready || !root.battPresent) return;
        if (root.battPlugged) root.plugIn();
        else if (root.alertVisible && root.mode === "charging") root.dismiss();
    }

    function plugIn() {
        root.plugged();
        // The card answers a warning -- so it only appears when there IS
        // one on screen to answer (asked for: "si je ne suis pas encore
        // au seuil et que l'alerte battery ne s'ouvre pas alors pas
        // besoin d'afficher quoi que ce soit"). A first pass also popped
        // it below the first tier with no alert up, on the theory that
        // the warning had just been dismissed; that's exactly the case
        // this rules out. Plugging in with nothing on screen is not an
        // event that needs the middle of the screen -- the `plugged()`
        // signal above still fires for it, and Battery.qml's pulse in
        // the top bar is the whole acknowledgement it gets.
        if (root.alertVisible) root.showCharging(root.battPercent);
    }

    function showCharging(p) {
        root.percent = p;
        root.critical = false;
        root.mode = "charging";
        root.alertVisible = true;
        chargingHide.restart();
    }

    // The low-battery card deliberately has NO auto-hide (it wants an
    // acknowledgement -- see BatteryAlert.qml's header). This one is the
    // opposite kind of message: it reports something that already
    // happened and needs no decision, so it leaves on its own, like the
    // OSD does. Long enough (4.5s) to still reach for "Balanced mode"
    // if that's what you wanted.
    Timer {
        id: chargingHide
        interval: 4500
        onTriggered: if (root.mode === "charging") root.dismiss()
    }

    function check() {
        if (!root.ready || !root.battPresent) return;
        if (!root.battDischarging) {
            if (root.battPercent > root.tiers[0] + 5) root.armedTier = 0;
            return;
        }
        while (root.armedTier < root.tiers.length && root.battPercent <= root.tiers[root.armedTier]) {
            root.show(root.battPercent, root.armedTier === root.tiers.length - 1);
            root.armedTier++;
        }
    }
    onBattPercentChanged: root.check()
    onBattDischargingChanged: root.check()

    function show(p, isCritical) {
        chargingHide.stop();
        root.mode = "low";
        root.percent = p;
        root.critical = isCritical;
        root.alertVisible = true;
    }

    // `mode` is deliberately NOT reset here: the card fades out over
    // 120ms, and flipping it back to "low" on the first frame of that
    // fade would recolor/re-label the card mid-dismiss. The next show()
    // sets it instead.
    function dismiss() {
        chargingHide.stop();
        root.alertVisible = false;
    }

    // "Low Power Mode" button -- a real action, not just decoration:
    // switches the system's power-profiles-daemon profile to
    // power-saver (`powerprofilesctl list` confirms it's available).
    // One-shot, launched on click like Bluetooth.qml's own pickerProc/
    // managerProc (Process with no `running: true`, set true on demand).
    Process {
        id: lowPowerProc
        command: ["powerprofilesctl", "set", "power-saver"]
    }
    function activateLowPowerMode() {
        lowPowerProc.running = true;
        root.dismiss();
    }

    // The mirror action, offered by the "charging" card: back on wall
    // power, the power-saver profile that the warning most likely just
    // talked you into is the thing you now want to undo. Same one-shot
    // Process shape as lowPowerProc above.
    Process {
        id: balancedProc
        command: ["powerprofilesctl", "set", "balanced"]
    }
    function activateBalancedMode() {
        balancedProc.running = true;
        root.dismiss();
    }

    // Manual trigger for previewing the alert without waiting on (or
    // owning) a real battery -- bypasses battPresent/discharging/tier
    // state entirely. `qs -c bar ipc call bar simulateBattery 8`
    // (wired up in shell.qml's IpcHandler).
    function simulate(percent) {
        const p = Math.max(0, Math.min(100, Math.round(percent)));
        root.show(p, p <= root.tiers[root.tiers.length - 1]);
    }

    // Same idea for the plug-in path -- fakes the discharging ->
    // plugged edge (signal included, so Battery.qml's pulse fires too)
    // without a charger or even a battery. Percent defaults to whatever
    // the card is already showing, which is what makes
    // `simulateBattery 8` then `simulatePlug` read exactly like
    // plugging in with the real warning on screen.
    function simulatePlug(percent) {
        const p = (percent === undefined || percent < 0)
            ? root.percent
            : Math.max(0, Math.min(100, Math.round(percent)));
        root.plugged();
        // Same gate as the real plugIn above, deliberately: a preview
        // that shows the card when a real charger wouldn't isn't a
        // preview of anything. `simulateBattery 8` then `simulatePlug`
        // still morphs the card; `simulatePlug` on its own now correctly
        // does nothing but pulse the top bar.
        if (root.alertVisible) root.showCharging(p);
    }
}
