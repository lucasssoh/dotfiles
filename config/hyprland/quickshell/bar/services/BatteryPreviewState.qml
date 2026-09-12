pragma Singleton
import QtQuick
import Quickshell

// Test-only override for Battery.qml's top-bar module. This desktop has
// no real laptop battery, so that module is normally invisible
// (present: false) -- this lets its percentage/charging render be
// PREVIEWED anyway, without touching real UPower state or
// power-profiles-daemon (unlike BatteryAlertState's simulate, which is
// for the low-battery ALERT; this is for the bar's own always-visible
// module, a visual preview only, no system side effect whatsoever).
//
// `qs -c bar ipc call bar previewBattery <percent> <charging>`,
// `qs -c bar ipc call bar previewBatteryConservation <on>` and
// `qs -c bar ipc call bar previewBatteryOff` (wired up in shell.qml).
Singleton {
    id: root

    property bool active: false
    property real percent: 100
    property bool charging: false
    // Lenovo conservation mode (the ~60% charge cap). Its own IPC call
    // rather than a third argument to set(): kept separate so it can be
    // toggled live, mid-preview, and the color swing actually watched --
    // and so the existing two-argument previewBattery call keeps working
    // unchanged.
    property bool conservation: false

    function set(p, isCharging) {
        root.percent = Math.max(0, Math.min(100, p));
        root.charging = isCharging;
        root.active = true;
    }

    function setConservation(on) {
        root.conservation = on;
        root.active = true;
    }

    function clear() {
        root.active = false;
    }
}
