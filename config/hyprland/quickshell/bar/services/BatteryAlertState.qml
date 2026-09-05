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

    readonly property var tiers: [20, 10, 5]   // last tier = critical
    property int armedTier: 0

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
        root.percent = p;
        root.critical = isCritical;
        root.alertVisible = true;
    }

    function dismiss() {
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

    // Manual trigger for previewing the alert without waiting on (or
    // owning) a real battery -- bypasses battPresent/discharging/tier
    // state entirely. `qs -c bar ipc call bar simulateBattery 8`
    // (wired up in shell.qml's IpcHandler).
    function simulate(percent) {
        const p = Math.max(0, Math.min(100, Math.round(percent)));
        root.show(p, p <= root.tiers[root.tiers.length - 1]);
    }
}
