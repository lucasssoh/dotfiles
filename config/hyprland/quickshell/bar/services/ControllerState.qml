pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Services.Pipewire
import "."
import "../theme"

// State + IPC for the controller popup. The pads themselves are read by the
// `manette` daemon (config/hyprland/manette-src), which only wakes for the
// Guide button and, while the popup is open, for the buttons that drive it;
// this file connects to its socket ($XDG_RUNTIME_DIR/manette.sock, JSON
// lines, same shape as Balise's) and decides what a press means.
//
// Guide, short press: opens the popup, except over Steam or a fullscreen
// window, where the press belongs to the game (Steam's own overlay sits on
// that button). Held: opens it whatever has focus. A pad without a Guide
// button gets there with Select + Start, which the daemon reports as held.
//
// While the popup is open the daemon holds the pads (EVIOCGRAB) and sends
// navigation here; the game behind sees nothing until it closes. Closing
// releases them, and so does this client going away, daemon-side.
Singleton {
    id: root

    readonly property string socketPath: Quickshell.env("XDG_RUNTIME_DIR") + "/manette.sock"

    // [{ id, name, family, bus, address, battery, charging }], as the daemon
    // describes them.
    property var pads: []
    readonly property bool hasPad: root.pads.length > 0
    // The pad the popup speaks about: the last one connected.
    readonly property var pad: root.hasPad ? root.pads[root.pads.length - 1] : null

    property bool open: false
    // True while the popup is on screen or fading out: the window, and the
    // whole popup with it, exists only then (see shell.qml).
    readonly property bool shown: root.open || lingerTimer.running
    property string screenName: ""
    // "home" | "apps"
    property string page: "home"
    // Navigation goes to whichever page is on screen.
    signal nav(string button)

    // The arrival banner: { name, family, bus, battery } while it shows.
    property var banner: null

    // Xbox pads over Bluetooth report their battery to BlueZ, not to the
    // driver: Balise has it, with the device path a "Turn off" needs.
    function btDeviceOf(p) {
        if (!p || p.bus !== "bluetooth" || !p.address) return null;
        const list = BaliseState.bluetoothDevices || [];
        for (let i = 0; i < list.length; i++) {
            if ((list[i].address || "").toLowerCase() === p.address) return list[i];
        }
        return null;
    }
    function batteryOf(p) {
        if (!p) return null;
        if (p.battery !== null && p.battery !== undefined) return p.battery;
        const d = root.btDeviceOf(p);
        return d && d.battery_percentage !== null && d.battery_percentage !== undefined ? d.battery_percentage : null;
    }
    readonly property var btDevice: root.btDeviceOf(root.pad)
    readonly property var battery: root.batteryOf(root.pad)

    // The installed Steam and Lutris games, newest played first, as the
    // daemon reads them each time the popup opens:
    // [{ id, title, source, last, cover, hero, launch: [argv] }].
    property var games: []

    readonly property real volume: OsdState.sinkVolume

    // How the pad in hand labels its buttons. The kernel names buttons by
    // position, so "south" confirms on every pad, the Switch included,
    // where that button is printed B. Tints are each brand's button
    // colours, desaturated to sit in the shell's greys; pads whose buttons
    // carry no colour stay in the primary ink.
    readonly property var labels: root._labels(root.pad ? root.pad.family : "generic")
    function _labels(family) {
        const ink = DrawerTheme.primary;
        // The tints are pastels made for the dark drawer; on the light one
        // they are taken down to a readable ink.
        const tone = (t) => DrawerTheme.dark ? t : Qt.darker(t, 2.0);
        const b = (kind, label, tint) => ({ kind: kind, label: label, tint: tint ? tone(tint) : ink });
        switch (family) {
        case "xbox":
            return { south: b("letter", "A", "#8fd49a"), east: b("letter", "B", "#ef8f8f"), north: b("letter", "Y", "#e9cf7d"), west: b("letter", "X", "#86aef0"), lb: "LB", rb: "RB", lt: "LT", rt: "RT", guide: "Guide" };
        case "playstation":
            return { south: b("cross", "", "#95b8f2"), east: b("circle", "", "#f09aa4"), north: b("triangle", "", "#86d6c8"), west: b("square", "", "#e7a6d4"), lb: "L1", rb: "R1", lt: "L2", rt: "R2", guide: "PS button" };
        case "nintendo":
            return { south: b("letter", "B"), east: b("letter", "A"), north: b("letter", "X"), west: b("letter", "Y"), lb: "L", rb: "R", lt: "ZL", rt: "ZR", guide: "Home" };
        case "steam":
            return { south: b("letter", "A"), east: b("letter", "B"), north: b("letter", "Y"), west: b("letter", "X"), lb: "L1", rb: "R1", lt: "L2", rt: "R2", guide: "Guide" };
        }
        return { south: b("dots", ""), east: b("dots", ""), north: b("dots", ""), west: b("dots", ""), lb: "L", rb: "R", lt: "L2", rt: "R2", guide: "Guide" };
    }

    function show() {
        if (root.open) return;
        root.screenName = Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : "";
        root.page = "home";
        root.open = true;
        root._send({ cmd: "grab" });
        root._send({ cmd: "refresh" });
        root._send({ cmd: "library" });
        if (root.pad && root.pad.bus === "bluetooth") BaliseState.refreshState();
    }

    function close() {
        if (!root.open) return;
        root.open = false;
        lingerTimer.restart();
        root._send({ cmd: "release" });
    }

    function launch(argv) {
        Quickshell.execDetached(argv);
        root.close();
    }

    // A game during a Boussole session asks first, here in the popup, with
    // the pad: A launches anyway (the session waits), B goes back to it.
    property var pendingLaunch: null
    function launchGame(argv) {
        if (BoussoleState.lockGames) {
            root.pendingLaunch = argv;
            root.page = "confirm";
            return;
        }
        root.launch(argv);
    }
    function confirmLaunch() {
        const argv = root.pendingLaunch;
        root.pendingLaunch = null;
        if (!argv) return;
        BoussoleState.pauseForGame();
        root.launch(argv);
    }

    function nudgeVolume(step) {
        const sink = Pipewire.defaultAudioSink;
        if (!sink || !sink.audio) return;
        sink.audio.muted = false;
        sink.audio.volume = Math.max(0, Math.min(1, Math.round((sink.audio.volume + step) * 20) / 20));
    }

    function turnOffPad() {
        if (root.btDevice) BaliseState.disconnectBluetooth(root.btDevice.path);
        root.close();
    }

    // A short Guide press is the game's while it has the screen.
    function _gameHasFocus() {
        const t = Hyprland.activeToplevel;
        const ipc = t ? (t.lastIpcObject || {}) : {};
        const cls = (ipc.class || ipc.initialClass || "").toLowerCase();
        return /steam|gamescope/.test(cls) || (ipc.fullscreen || 0) > 0;
    }

    function _handleLine(line) {
        let msg;
        try {
            msg = JSON.parse(line);
        } catch (e) {
            return;
        }
        if (msg.event === "pads") {
            if (JSON.stringify(msg.pads) !== JSON.stringify(root.pads)) root.pads = msg.pads || [];
            // A Bluetooth pad already there when the bar starts: its battery
            // is in Balise's device list, which may not be loaded yet.
            if (root.pad && root.pad.bus === "bluetooth" && !root.btDevice) BaliseState.refreshState();
            if (root.open && !root.hasPad) root.close();
        } else if (msg.event === "library") {
            const g = (msg.games || []).slice().sort((a, b) => (b.last || 0) - (a.last || 0) || a.title.localeCompare(b.title));
            if (JSON.stringify(g) !== JSON.stringify(root.games)) root.games = g;
        } else if (msg.event === "connected") {
            root.banner = msg.pad;
            if (msg.pad.bus === "bluetooth") BaliseState.refreshState();
            bannerTimer.restart();
        } else if (msg.event === "guide") {
            if (root.open) root.close();
            else if (msg.long || !root._gameHasFocus()) root.show();
        } else if (msg.event === "nav") {
            if (!root.open) return;
            if (msg.button === "guide") root.close();
            else if (msg.button === "lb") root.nudgeVolume(-0.05);
            else if (msg.button === "rb") root.nudgeVolume(0.05);
            else root.nav(msg.button);
        }
    }

    // Outlives the close by the fade, so the popup is not cut mid-animation.
    Timer {
        id: lingerTimer
        interval: 220
    }

    Timer {
        id: bannerTimer
        interval: 3000
        onTriggered: root.banner = null
    }

    function _send(obj) {
        const sock = socketLoader.item;
        if (!sock || !sock.connected) return false;
        sock.write(JSON.stringify(obj) + "\n");
        sock.flush();
        return true;
    }

    readonly property bool daemonConnected: socketLoader.item ? socketLoader.item.connected : false

    // The daemon restarted (or the bar did) with the popup open: the grab
    // went with the old connection, so the popup goes too.
    onDaemonConnectedChanged: {
        if (!root.daemonConnected) root.open = false;
    }

    // Rebuilt rather than reconnected, for the reason BaliseState.qml gives:
    // a Quickshell Socket never comes back once it has failed.
    Loader {
        id: socketLoader
        active: true
        sourceComponent: Component {
            Socket {
                path: root.socketPath
                connected: true
                parser: SplitParser {
                    splitMarker: "\n"
                    onRead: (line) => root._handleLine(line)
                }
            }
        }
    }

    // Backs off to a try every 30s, so a machine without the daemon pays
    // next to nothing for looking.
    Timer {
        id: reconnectTimer
        property int tries: 0
        interval: Math.min(30000, 2000 * Math.pow(2, Math.min(tries, 4)))
        repeat: true
        running: !root.daemonConnected
        onRunningChanged: if (!running) tries = 0
        onTriggered: {
            tries++;
            socketLoader.active = false;
            socketLoader.active = true;
        }
    }
}
