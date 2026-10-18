pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Networking

// Root is Quickshell's own `Singleton` type (not plain QtObject) --
// same "singleton" word, different thing: `pragma Singleton` above is
// the QML-language mechanism that makes every `import "../services"`
// share one instance; Quickshell.Singleton is the element TYPE that
// instance is built from, needed here (instead of QtObject) purely
// because it has a default `children` property, so the Loader and Timer
// below can be declared as direct children -- QtObject has no default
// property and rejects them.

// The bar's system figures, from Pouls (pouls-src/, pouls.service) over
// $XDG_RUNTIME_DIR/pouls.sock. This file used to sample them itself: nine
// FileView reloads every 3 s, each one a job on Qt's thread pool, about 18
// thread wakeups a tick measured on the IdeaPad, screen on or off. Pouls
// keeps the files open, reads them with one wakeup of its own, pushes only
// what the modules would draw differently, and stops sampling while nobody
// looks: in zen mode (`watching` below, bound from shell.qml) and while the
// screen is off (idle-action.sh tells it). The charger and the charge
// policy come from the kernel's uevents instead of a re-read every tick.
//
// One instance for every monitor's bar: every number here is system-wide,
// and each bar's modules bind to these properties.
//
// Traffic's WHICH-INTERFACE-IS-ACTIVE half stays here, from
// Quickshell.Networking: NetworkManager pushes it over DBus. Pouls is told
// the interface and samples its rx_bytes, the one part with no push.
Singleton {
    id: root

    // False in zen mode: no figure is on screen, so Pouls stops sampling.
    property bool watching: true

    // ---- Cpu.qml ----
    property int cpuUsage: 0
    property real cpuMaxGhz: 0

    // ---- Memory.qml ----
    property real memUsedGB: 0
    property int memUsedPct: 0

    // ---- Temperature.qml / Fan.qml ----
    // False until Pouls has found a sensor; the modules hide meanwhile.
    property bool hasTemp: false
    property int tempCelsius: 0
    property bool hasFan: false
    property string fanRpm: "N/A"

    // ---- Battery.qml / PowerHome.qml (Lenovo conservation mode) ----
    // The EC's binary ~60 % cap. Only IdeaPads expose it; hasConservation
    // stays false everywhere else and Battery.qml's colour behaves as before.
    property bool hasConservation: false
    property bool conservationMode: false

    // ---- PowerHome.qml (Lenovo fast charge) ----
    // The EC's charge-current policy, which it may drop back to Standard by
    // itself, on unplug, on resume or when the pack gets hot. Nothing here
    // latches the toggle on: the tile follows what Pouls reads back.
    property bool fastChargeAvailable: false
    property bool fastCharge: false

    // ---- BatteryAlertState (charger dropped) ----
    // A 45 W brick latches off in overcurrent protection while staying
    // negotiated; Pouls tells it from an unplug (pouls-src/src/power.rs has
    // the measurements) and sends adapterDropped.
    property bool hasMains: false
    property bool mainsOnline: false
    signal adapterDropped()

    // ---- Traffic.qml ----
    // Ethernet beats wifi if both happen to be connected -- same
    // priority the old nmcli script used. Reactive: re-evaluates
    // whenever Networking.devices' membership or any device's
    // `connected` changes, no polling involved.
    readonly property var activeDevice: {
        const devices = Networking.devices.values;
        let wifi = null;
        for (let i = 0; i < devices.length; i++) {
            const d = devices[i];
            if (!d.connected) continue;
            if (d.type === DeviceType.Wired) return d;
            if (d.type === DeviceType.Wifi) wifi = d;
        }
        return wifi;
    }
    readonly property string netIface: activeDevice ? activeDevice.name : ""
    readonly property string netKind: !activeDevice ? "none" : (activeDevice.type === DeviceType.Wired ? "ethernet" : "wifi")
    property real netRateBps: 0

    onNetIfaceChanged: root._send({ cmd: "iface", name: root.netIface })
    onWatchingChanged: root._send({ cmd: "watch", on: root.watching })

    // Written by Pouls, which the udev rules let the session do; it reads
    // the attribute back, so the tile snaps back if the kernel refused.
    function setConservation(on) { root._send({ cmd: "conservation", on: on }); }
    function setFastCharge(on) { root._send({ cmd: "fastCharge", on: on }); }

    function _handleLine(line) {
        let m;
        try { m = JSON.parse(line); } catch (e) { return; }
        if (m.event === "stats") {
            root.cpuUsage = m.cpu;
            root.cpuMaxGhz = m.ghz;
            root.memUsedGB = m.memGB;
            root.memUsedPct = m.memPct;
            root.hasTemp = m.hasTemp;
            root.tempCelsius = m.temp === null ? 0 : m.temp;
            root.hasFan = m.hasFan;
            root.fanRpm = m.fan === null ? "N/A" : String(m.fan).padStart(4, " ");
            root.netRateBps = m.net;
        } else if (m.event === "power") {
            root.hasMains = m.hasMains;
            root.mainsOnline = m.mains;
            root.hasConservation = m.hasConservation;
            root.conservationMode = m.conservation;
            root.fastChargeAvailable = m.fastChargeAvailable;
            root.fastCharge = m.fastCharge;
        } else if (m.event === "adapterDropped") {
            root.adapterDropped();
        }
    }

    function _send(obj) {
        const sock = socketLoader.item;
        if (!sock || !sock.connected) return false;
        sock.write(JSON.stringify(obj) + "\n");
        sock.flush();
        return true;
    }

    readonly property bool daemonConnected: socketLoader.item ? socketLoader.item.connected : false

    // A new connection starts with nothing: Pouls only sends figures to a
    // client that has said it watches, for the interface it was given.
    onDaemonConnectedChanged: {
        if (!root.daemonConnected) return;
        root._send({ cmd: "iface", name: root.netIface });
        root._send({ cmd: "watch", on: root.watching });
    }

    // Rebuilt rather than reconnected, for the reason BaliseState.qml gives:
    // a Quickshell Socket never comes back once it has failed.
    Loader {
        id: socketLoader
        active: true
        sourceComponent: Component {
            Socket {
                path: Quickshell.env("XDG_RUNTIME_DIR") + "/pouls.sock"
                connected: true
                parser: SplitParser {
                    splitMarker: "\n"
                    onRead: (line) => root._handleLine(line)
                }
            }
        }
    }

    // Backs off to a try every 30s, like ControllerState's.
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
