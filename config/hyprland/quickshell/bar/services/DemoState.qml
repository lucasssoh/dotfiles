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
//   - CPU, frequency, memory, temperature, power draw and network rate (SystemStats
//     ignores Pouls's figures meanwhile);
//   - Programme's indicator, which shows `event`;
//   - the Wi-Fi name in Balise;
//   - what's playing, `player` in place of your own.
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
    readonly property real watts: 4.8

    // What's playing, in place of your own player: the centre and the
    // bar's island read it as they read an MPRIS player. It stands still
    // (the elapsed time never moves), so every take matches; play/pause
    // only swaps its glyph.
    readonly property QtObject player: QtObject {
        readonly property string dbusName: "demo"
        readonly property string identity: "Music"
        readonly property string trackTitle: "December Dream"
        readonly property string trackArtist: "Fourplay"
        readonly property string trackArtUrl: ""
        property bool isPlaying: true
        readonly property bool canGoPrevious: true
        readonly property bool canGoNext: true
        readonly property bool canTogglePlaying: true
        readonly property bool positionSupported: true
        readonly property real position: 107
        readonly property bool lengthSupported: true
        readonly property real length: 343
        readonly property int uniqueId: 1
        function togglePlaying() { isPlaying = !isPlaying; }
        function next() {}
        function previous() {}
    }

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
        SystemStats.hasWatts = true;
        SystemStats.watts = root.watts;
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
