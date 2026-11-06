pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Demo mode: the bar shows the same made-up figures every time, for
// screenshots and videos. Light and dark captures then match to the pixel,
// and nothing personal appears: no real agenda, no network name.
//
// What it changes, and only on screen:
//   - the time, frozen through ShellClock;
//   - the battery, through BatteryPreviewState;
//   - CPU, frequency, memory, temperature and network rate (SystemStats
//     ignores Pouls's figures meanwhile);
//   - Programme's indicator, which shows `event`;
//   - the Wi-Fi name in Balise.
// Notifications that arrive while it is on are closed when it ends, so
// the ones a capture sends never stay in your history.
//
//   qs -c bar ipc call demo on
//   qs -c bar ipc call demo off
//   qs -c bar ipc call demo status
Singleton {
    id: root

    property bool active: false

    readonly property string clock: "10:42:00"
    readonly property string event: "Café avec Inès · 14:00"
    readonly property string wifi: "Maison"
    readonly property int battery: 76
    readonly property int cpu: 4
    readonly property real ghz: 1.6
    readonly property real memGB: 2.4
    readonly property int memPct: 15
    readonly property int temp: 41
    readonly property real netBps: 1200

    // Notifications received while active, closed by off().
    property var _notifications: []

    function track(n) {
        if (root.active) root._notifications = root._notifications.concat([n]);
    }

    function on() {
        if (root.active) return;
        root.active = true;
        ShellClock.freezeTime(root.clock);
        BatteryPreviewState.set(root.battery, false);
        SystemStats.cpuUsage = root.cpu;
        SystemStats.cpuMaxGhz = root.ghz;
        SystemStats.memUsedGB = root.memGB;
        SystemStats.memUsedPct = root.memPct;
        SystemStats.tempCelsius = root.temp;
        SystemStats.netRateBps = root.netBps;
    }

    function off() {
        if (!root.active) return;
        root.active = false;
        ShellClock.reset();
        BatteryPreviewState.clear();
        // Pouls's next report, a second or two away, brings the real
        // figures back.
        for (const n of root._notifications) {
            if (NotificationState.isTracked(n)) n.dismiss();
        }
        root._notifications = [];
    }

    IpcHandler {
        target: "demo"

        function on(): void { root.on(); }
        function off(): void { root.off(); }
        function status(): string { return root.active ? "on" : "off"; }
    }
}
