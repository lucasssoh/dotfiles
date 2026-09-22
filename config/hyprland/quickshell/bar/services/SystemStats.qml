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

    // ---- Battery.qml (Lenovo conservation mode) ----
    // The one value sampled here that is NOT a rate (see this file's
    // header): a plain boolean flag. It lives here anyway for the OTHER
    // half of that header's argument -- it's system-wide state, so a
    // per-module read would run once per monitor, on its own timer, for
    // the same byte. There is also no DBus push for it: UPower reports
    // the battery, not the EC policy capping it.
    //
    // Lenovo IdeaPad only: the EC exposes a binary ~60% cap, and
    // ideapad-laptop.ko exports `conservation_mode` and nothing else
    // (ThinkPads get the generic charge_control_*_threshold knobs
    // instead -- verified against both module binaries, see
    // scripts/lib/hardware.sh's own note). conservationPath stays empty
    // on every other machine and Battery.qml's color then behaves
    // exactly as it did before.
    property string conservationPath: ""
    property bool conservationMode: false

    // ---- Battery.qml (Lenovo fast charge) ----
    // The EC's charge-current policy, a separate attribute from the cap
    // above and on a DIFFERENT device: conservation_mode belongs to the
    // ideapad_acpi platform device, charge_types to the ACPI battery.
    // Hence a second discovery below rather than a second read off the
    // same path.
    //
    // sysfs "list with the active entry in brackets" -- reading it gives
    // `Fast [Standard] Long_Life`, and writing takes one bare word. The
    // EC picks Standard on its own; Fast is worth ~68% more charge power
    // (41.5 W -> 69.9 W measured, see 99-ideapad-fastcharge.rules), at
    // ~1.0C instead of ~0.7C, which is why it is a deliberate toggle and
    // not something set once at boot.
    //
    // fastChargeAvailable is its own property rather than
    // `chargeTypesPath !== ""`: a battery can expose charge_types while
    // offering only Standard and Long_Life, and a tile that cannot reach
    // the mode it is named after should not be drawn.
    property string chargeTypesPath: ""
    property bool fastChargeAvailable: false
    property bool fastCharge: false

    // ---- BatteryAlertState (chargeur decroche) ----
    // A 45W USB-C brick on this machine gets asked for 46-53W while the
    // battery is charging hard (38-44W into the cell plus ~6W of system,
    // measured), trips its own overcurrent protection after a while, and
    // LATCHES OFF: the PD contract stays negotiated, the port stays a
    // sink, the charger is still visibly attached -- but the EC's mains
    // line goes to 0 and the machine quietly runs down the battery. It
    // does not come back on its own; only a physical replug clears it.
    // Observed twice, 18min30 then 5min00 apart (the second trip comes
    // sooner because the brick never cooled), at 71% and 75% -- which is
    // exactly what looked like a "cap at 65%" for months: starting from
    // roughly half charge, the countdown always expired in the mid-60s.
    //
    // Distinguishing that from an ordinary unplug is the whole job here,
    // and `power_role` is NOT the way: it was found stuck at [sink] with
    // nothing attached at all, minutes after the cable came out. The two
    // attributes that do track reality are the presence of the port's
    // `-partner` directory and `power_operation_mode`:
    //
    //                      -partner   power_operation_mode   power_role
    //   unplugged           absent    default                [source]
    //   charging            present   usb_power_delivery     [sink]
    //   DROPPED             present   usb_power_delivery     [sink]
    //   unplugged (later)   absent    default                [sink]   <- stale
    //
    // So: mains offline while a PD partner is still attached == dropped.
    property string mainsPath: ""
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
    FileView { id: conservationFile; blockLoading: true }
    FileView { id: chargeTypesFile; blockLoading: true }
    FileView { id: mainsFile; blockLoading: true }
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

    // The one WRITE in this file. It lives here because this is where
    // conservationPath was discovered -- a setter anywhere else would have
    // to repeat that glob or import it back from here anyway.
    //
    // Works without any privilege escalation: config/hyprland/udev/
    // 99-ideapad-conservation.rules hands the attribute to group wheel at
    // device-add time (installed by scripts/install-hardware.sh). Without
    // that rule the attribute is root:root 0644 and this write silently
    // fails -- hence the re-sample afterwards rather than assuming it took,
    // so the UI snaps back if the kernel did not accept it.
    function setConservation(on) {
        if (root.conservationPath === "") return;
        conservationWriter.command = ["sh", "-c",
            "printf '%s' " + (on ? "1" : "0") + " > " + root.conservationPath];
        conservationWriter.running = true;
    }

    Process {
        id: conservationWriter
        onExited: root.sampleConservation()
    }

    function sampleConservation() {
        if (root.conservationPath === "") return;
        conservationFile.reload();
        conservationFile.waitForJob();   // see sampleCpu's note: reload() alone only queues an async re-read
        root.conservationMode = conservationFile.text().trim() === "1";
    }

    // The file's second write, and it works the same way as the first:
    // 99-ideapad-fastcharge.rules hands charge_types to group wheel, so
    // no escalation happens here either, and the re-sample afterwards is
    // what makes the UI snap back if the kernel refused the value.
    //
    // Refusal is a live possibility rather than a theoretical one: the EC
    // rejects a mode it does not currently allow (-EINVAL out of sysfs's
    // own match against the bracketed list), and it is also free to drop
    // back to Standard by itself -- on unplug, on resume, or when the
    // pack gets hot. Nothing here latches the toggle on; the tick below
    // re-reads the attribute every 3s and the tile follows whatever the
    // EC actually settled on.
    function setFastCharge(on) {
        if (!root.fastChargeAvailable) return;
        chargeTypesWriter.command = ["sh", "-c",
            "printf '%s' " + (on ? "Fast" : "Standard") + " > " + root.chargeTypesPath];
        chargeTypesWriter.running = true;
    }

    Process {
        id: chargeTypesWriter
        onExited: root.sampleFastCharge()
    }

    function sampleFastCharge() {
        if (root.chargeTypesPath === "") return;
        chargeTypesFile.reload();
        chargeTypesFile.waitForJob();   // see sampleCpu's note
        const text = chargeTypesFile.text();
        // Only the BRACKETED word is the active mode. A plain
        // indexOf("Fast") would be true permanently, since Fast is listed
        // whether or not it is selected -- the tile would light up at
        // boot and never go out.
        const active = text.match(/\[([^\]]+)\]/);
        root.fastCharge = active !== null && active[1] === "Fast";
        root.fastChargeAvailable = text.indexOf("Fast") !== -1;
    }

    function sampleMains() {
        if (root.mainsPath === "") return;
        mainsFile.reload();
        mainsFile.waitForJob();   // see sampleCpu's note
        root.mainsOnline = mainsFile.text().trim() === "1";
    }

    // Edge-triggered, not polled: the ONLY moment worth inspecting the
    // USB-C side is the mains 1 -> 0 transition. Checking every tick
    // would fork a shell every 3s for the whole time the laptop runs on
    // battery -- the exact cost this file's header exists to avoid --
    // to answer a question that can only change on that edge.
    //
    // Two seconds of settle first: on a REAL unplug the typec layer
    // needs a moment to tear the partner down, and inspecting inside
    // that window would read the still-present partner and cry wolf.
    // The latched-off state, by contrast, persists indefinitely -- it
    // was still readable 14s and again 42s after the drop -- so nothing
    // is lost by waiting.
    onMainsOnlineChanged: {
        if (root.mainsPath === "") return;
        if (root.mainsOnline) { adapterSettle.stop(); return; }
        adapterSettle.restart();
    }

    Timer {
        id: adapterSettle
        interval: 2000
        onTriggered: adapterVerdict.running = true
    }

    Process {
        id: adapterVerdict
        command: ["bash", "-c",
            "for p in /sys/class/typec/port*; do " +
            "[ -e \"$p-partner\" ] || continue; " +
            "[ \"$(cat $p/power_operation_mode 2>/dev/null)\" = usb_power_delivery ] && { echo dropped; exit 0; }; " +
            "done; echo gone"]
        stdout: StdioCollector {
            onStreamFinished: {
                if (this.text.trim() === "dropped") root.adapterDropped();
            }
        }
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

    // Same resolve-once pattern for the thermal sensor, but by PREFERENCE
    // rather than by glob order. Taking the first thermal_zone was wrong on
    // both vendors: thermal_zone0 is `acpitz` on this machine and on most
    // Intel laptops, i.e. a board/skin sensor that lags the die by seconds
    // and flattens out under load -- not the CPU package temperature the
    // bar is meant to show. So: x86_pkg_temp first (Intel package), then
    // the coretemp/k10temp hwmon (Intel/AMD die), and only then fall back
    // to whatever thermal zone exists, for a machine that exposes none of
    // them. All four sources report millidegrees, so sampleTemperature's
    // /1000 holds regardless of which one wins.
    // Temperature.qml gates its own visibility on tempPath being non-empty,
    // same as Fan.qml does for fanPath.
    Process {
        id: tempDiscover
        command: ["bash", "-c", "{ grep -lx x86_pkg_temp /sys/class/thermal/thermal_zone*/type; grep -lx coretemp /sys/class/hwmon/hwmon*/name; grep -lx k10temp /sys/class/hwmon/hwmon*/name; } 2>/dev/null | head -n1 | sed -e 's@/type$@/temp@' -e 's@/name$@/temp1_input@' | grep . || find /sys/class/thermal/thermal_zone*/temp 2>/dev/null | head -n1"]
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

    // Same discover-once pattern as the fan/thermal probes above. Searched
    // under /sys/bus/platform/devices/ rather than through
    // /sys/bus/platform/drivers/<name>/: the driver's registered name and
    // its place in the module tree both move between kernel releases
    // (ideapad-laptop moved into a lenovo/ subdirectory in 7.1), the
    // attribute's own name does not.
    //
    // NOT /sys/devices/platform, which is what this looked in first and
    // which found nothing on the actual IdeaPad: that directory only
    // holds the platform devices whose PARENT is the platform bus root,
    // and VPC2004:00 is not one of them -- ideapad-laptop binds an ACPI
    // node, so the device lives at
    // /sys/devices/pci0000:00/0000:00:1f.0/PNP0C09:00/VPC2004:00 and
    // never appeared under that path at all. /sys/bus/platform/devices/
    // is the bus-wide view and lists every platform device by name
    // wherever it is parented, which is the property actually wanted
    // here.
    //
    // -L is load-bearing: those entries are symlinks back into
    // /sys/devices, and find without it does not descend into a symlink,
    // so it silently matches nothing -- the same empty result as the
    // wrong path, for a completely different reason. -maxdepth 2 keeps
    // it to one directory level per device instead of walking all of
    // /sys/devices through the links.
    Process {
        id: conservationDiscover
        command: ["bash", "-c", "find -L /sys/bus/platform/devices -maxdepth 2 -name conservation_mode 2>/dev/null | head -n1"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                root.conservationPath = this.text.trim();
                if (root.conservationPath !== "") {
                    conservationFile.path = root.conservationPath;
                    root.sampleConservation();
                }
            }
        }
    }

    // The AC adapter's own online flag. Matched on type == "Mains"
    // rather than hardcoding "ADP1": that name is an ACPI artefact and
    // is "AC"/"ACAD" on plenty of machines. Resolved once, same shape as
    // every other discovery above; stays empty on a desktop, which
    // leaves the whole drop detection inert.
    Process {
        id: mainsDiscover
        command: ["bash", "-c",
            "for d in /sys/class/power_supply/*/; do " +
            "[ \"$(cat $d/type 2>/dev/null)\" = Mains ] && { echo \"${d}online\"; exit 0; }; " +
            "done"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                root.mainsPath = this.text.trim();
                if (root.mainsPath !== "") {
                    mainsFile.path = root.mainsPath;
                    root.sampleMains();
                }
            }
        }
    }

    // charge_types, on the BATTERY rather than on the mains supply or on
    // the ideapad platform device -- so this is a third discovery, not a
    // reuse of either path above. Same shape as mainsDiscover: walk
    // /sys/class/power_supply and match on `type` rather than trusting
    // "BAT0" to be the name, since it is an ACPI artefact.
    //
    // The [ -e ] test is the real filter. Every laptop has a Battery
    // here; almost none expose charge_types, and on those the path stays
    // empty and the tile is never drawn.
    Process {
        id: chargeTypesDiscover
        command: ["bash", "-c",
            "for d in /sys/class/power_supply/*/; do " +
            "[ \"$(cat $d/type 2>/dev/null)\" = Battery ] && [ -e \"$d/charge_types\" ] " +
            "&& { echo \"${d}charge_types\"; exit 0; }; " +
            "done"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                root.chargeTypesPath = this.text.trim();
                if (root.chargeTypesPath !== "") {
                    chargeTypesFile.path = root.chargeTypesPath;
                    root.sampleFastCharge();
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
            root.sampleConservation();
            root.sampleFastCharge();
            root.sampleMains();
            root.sampleTraffic();
        }
    }
}
