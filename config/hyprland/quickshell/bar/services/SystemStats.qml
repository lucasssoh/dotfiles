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
// because it has a default `children` property, so the Process/FileView/
// Timer objects below can be declared as direct children like they were
// in Item-rooted Cpu.qml etc. -- QtObject has no default property and
// rejects them.

// One shared sampler for every METRICS stat that has NO kernel/DBus push
// equivalent -- see Battery.qml (UPower) and AudioOutput.qml (Pipewire)
// for the two stats that DO get one for free; CPU/memory/temperature/fan
// and the network rate don't, because all five are *rates*, computed
// from a delta between two reads a few seconds apart. There's no signal
// for "usage changed" the way there's a PropertiesChanged for "battery
// percent changed" -- something has to keep sampling.
//
// Why centralize that here instead of each module polling on its own
// (Cpu.qml/Memory.qml/Temperature.qml/Fan.qml each used to, and
// Traffic.qml's header used to explicitly defend following the same
// per-module convention): the bar is instantiated once PER MONITOR
// (shell.qml's `Variants { model: Quickshell.screens }`), and every one
// of these numbers is system-wide, not per-monitor -- CPU usage on
// screen 1 and screen 2 is the same number. Two monitors used to mean
// 2x /proc/stat reads, 2x /proc/meminfo reads, 2x thermal_zone0 reads,
// 2x fan hwmon reads -- all sampling the exact same system state, on
// independent timers, for no benefit. This file samples once; every bar
// instance's module just binds to these properties instead of sampling
// itself.
//
// Traffic's WHICH-INTERFACE-IS-ACTIVE half used to be polled here too
// (a persistent `nmcli monitor` watcher + a re-run `nmcli`/awk script on
// every change). Quickshell.Networking wraps NetworkManager's own DBus
// objects directly -- same family as Battery.qml/AudioOutput.qml -- so
// activeDevice/netIface/netKind below are plain reactive bindings now,
// pushed by NetworkManager, zero nmcli process anywhere in this file.
// It's ALSO already a Quickshell-native singleton, so Network.qml and
// Ethernet.qml binding to it directly (not through here) costs nothing
// extra either -- unlike the old nmcli-based version, there's no
// per-consumer duplication left to centralize. Only rx_bytes itself
// still needs sampling below: byte counters have no DBus push
// equivalent, same reasoning as CPU/memory/temperature/fan above.
Singleton {
    id: root

    // ---- Cpu.qml ----
    property real prevCpuTotal: -1
    property real prevCpuIdle: -1
    property int cpuUsage: 0
    property real cpuMaxGhz: 0

    // ---- Memory.qml ----
    property real memUsedGB: 0
    property int memUsedPct: 0

    // ---- Temperature.qml ----
    // thermal_zone path glob-discovered once at startup, same pattern as
    // Fan.qml's hwmon discovery below -- thermal_zone0 isn't guaranteed to
    // be the CPU package sensor (or to exist at all) on every machine.
    property string tempPath: ""
    property int tempCelsius: 0

    // ---- Fan.qml ----
    property string fanPath: ""
    property string fanRpm: "N/A"

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
    property real prevNetBytes: -1
    property real netRateBps: 0

    onNetIfaceChanged: {
        prevNetBytes = -1;   // new interface -> discard the old delta baseline
        rxFile.path = netIface !== "" ? "/sys/class/net/" + netIface + "/statistics/rx_bytes" : "";
    }

    // Shared tick for everything above. All five reads are tiny (a few
    // hundred bytes off sysfs/procfs via FileView, no subprocess fork on
    // the hot path), so there's no real cost to sampling
    // memory/temperature/fan at Cpu's old faster 3s cadence instead of
    // their old individual 5s/5s/10s -- the previous staggered intervals
    // didn't save anything real, they just meant 4 separate Timer
    // objects (x2 per monitor) instead of 1.
    readonly property int tickMs: 3000

    FileView { id: statFile; path: "/proc/stat"; blockLoading: true }
    FileView { id: cpuInfoFile; path: "/proc/cpuinfo"; blockLoading: true }
    FileView { id: memFile; path: "/proc/meminfo"; blockLoading: true }
    FileView { id: tempFile; blockLoading: true }
    FileView { id: fanFile; blockLoading: true }
    FileView { id: rxFile; blockLoading: true }

    function sampleCpu() {
        statFile.reload();
        statFile.waitForJob();   // reload() alone queues an async re-read -- see pokeBrightness's comment in OsdState.qml, found the hard way
        const line = statFile.text().split("\n")[0];
        const parts = line.trim().split(/\s+/).slice(1).map(Number);
        const idle = parts[3] + parts[4];
        const total = parts.reduce((a, b) => a + b, 0);
        if (root.prevCpuTotal >= 0) {
            const dTotal = total - root.prevCpuTotal;
            const dIdle = idle - root.prevCpuIdle;
            root.cpuUsage = dTotal > 0 ? Math.round(100 * (1 - dIdle / dTotal)) : 0;
        }
        root.prevCpuTotal = total;
        root.prevCpuIdle = idle;

        cpuInfoFile.reload();
        cpuInfoFile.waitForJob();
        const matches = cpuInfoFile.text().match(/cpu MHz\s*:\s*([\d.]+)/g) || [];
        let maxMhz = 0;
        for (let i = 0; i < matches.length; i++) {
            const v = parseFloat(matches[i].split(":")[1]);
            if (v > maxMhz) maxMhz = v;
        }
        root.cpuMaxGhz = maxMhz / 1000;
    }

    function sampleMemory() {
        memFile.reload();
        memFile.waitForJob();
        const lines = memFile.text().split("\n");
        let total = 0, avail = 0;
        for (let i = 0; i < lines.length; i++) {
            const l = lines[i];
            if (l.indexOf("MemTotal:") === 0) total = parseInt(l.split(/\s+/)[1]);
            else if (l.indexOf("MemAvailable:") === 0) avail = parseInt(l.split(/\s+/)[1]);
        }
        const usedKB = total - avail;
        root.memUsedGB = usedKB / 1024 / 1024;
        root.memUsedPct = total > 0 ? Math.round(100 * usedKB / total) : 0;
    }

    function sampleTemperature() {
        if (root.tempPath === "") return;
        tempFile.reload();
        tempFile.waitForJob();
        const raw = parseInt(tempFile.text().trim());
        root.tempCelsius = isNaN(raw) ? 0 : Math.round(raw / 1000);
    }

    function sampleFan() {
        if (root.fanPath === "") return;
        fanFile.reload();
        fanFile.waitForJob();
        const v = parseInt(fanFile.text().trim());
        root.fanRpm = isNaN(v) ? "N/A" : String(v).padStart(4, " ");
    }

    function sampleTraffic() {
        if (root.netIface === "") { root.netRateBps = 0; return; }
        rxFile.reload();
        rxFile.waitForJob();
        const v = parseInt(rxFile.text().trim());
        if (isNaN(v)) return;
        if (root.prevNetBytes >= 0)
            root.netRateBps = Math.max(0, (v - root.prevNetBytes) / (root.tickMs / 1000));
        root.prevNetBytes = v;
    }

    // Fan's hwmon path needs a glob (fan1_input under hwmon0, hwmon1,
    // ... -- the number isn't stable across machines), resolved ONCE
    // here at startup, same as Fan.qml used to do per-instance.
    Process {
        id: fanDiscover
        command: ["bash", "-c", "find /sys/class/hwmon/hwmon*/fan1_input 2>/dev/null | head -n1"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                root.fanPath = this.text.trim();
                if (root.fanPath !== "") {
                    fanFile.path = root.fanPath;
                    root.sampleFan();
                }
            }
        }
    }

    // Same glob-and-resolve-once pattern for the thermal sensor:
    // thermal_zone0 isn't guaranteed to exist or to be the CPU package
    // sensor on every machine. Temperature.qml gates its own visibility on
    // tempPath being non-empty, same as Fan.qml does for fanPath.
    Process {
        id: tempDiscover
        command: ["bash", "-c", "find /sys/class/thermal/thermal_zone*/temp 2>/dev/null | head -n1"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                root.tempPath = this.text.trim();
                if (root.tempPath !== "") {
                    tempFile.path = root.tempPath;
                    root.sampleTemperature();
                }
            }
        }
    }

    Timer {
        interval: root.tickMs
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            root.sampleCpu();
            root.sampleMemory();
            root.sampleTemperature();
            root.sampleFan();
            root.sampleTraffic();
        }
    }
}
