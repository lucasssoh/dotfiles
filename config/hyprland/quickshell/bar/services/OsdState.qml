pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire

// State + trigger logic for the volume/mic/brightness OSD (Osd.qml
// renders it, one instance per screen via shell.qml's Variants). Two
// very different data sources feed it:
//
// Volume + mic: zero poll -- watches the SAME live Pipewire.
// defaultAudioSink/defaultAudioSource properties AudioOutput.qml/
// AudioInput.qml already read (see those files' headers), and calls
// show() whenever volume/muted changes. No new plumbing, no keybinds.lua
// changes needed -- this reacts to the actual audio state, not to the
// keypress, so it also fires correctly for a volume change made outside
// this bar (pavucontrol, a hardware knob, another app).
//
// Brightness: no DBus/kernel push exists for backlight level the way
// there's one for volume. /sys/class/backlight/*/brightness is a sysfs
// kernfs attribute -- notified via poll()/uevent (what udev and
// brightnessctl itself use internally), NOT inotify, so Quickshell's
// FileView watchChanges (Qt's QFileSystemWatcher, inotify-based) can't
// reliably catch a change made by another process. Kept simple instead:
// keybinds.lua calls `quickshell ipc call -c bar bar pokeBrightness`
// right after brightnessctl -- same IPC pattern zen mode already uses
// (see shell.qml's IpcHandler) -- and pokeBrightness() below does one
// cheap sysfs FileView.reload(), no brightnessctl/bash spawn on this
// side either.
//
// Battery-low is a SEPARATE surface (BatteryAlertState.qml/
// BatteryAlert.qml) -- a centered, click-to-dismiss modal styled after
// iOS/macOS's own "Low Battery" alert, not this transient corner popup.
// It doesn't belong here: this OSD auto-hides on a timer and is meant to
// be glanced at, not interacted with, which is wrong for a warning that
// wants an acknowledgement.
Singleton {
    id: root

    property bool osdVisible: false
    property string kind: "volume"   // "volume" | "mic" | "brightness"
    property real level: 0           // 0-1
    property bool muted: false

    // Guards against a spurious flash right after startup/hot-reload,
    // while Pipewire's defaultAudioSink/Source are still connecting --
    // that null -> real node transition is a real property change, not
    // a user action, and shouldn't pop the OSD.
    property bool ready: false
    Timer { interval: 600; running: true; onTriggered: root.ready = true }

    function show(newKind, newLevel, newMuted) {
        if (!root.ready) return;
        root.kind = newKind;
        root.level = newLevel;
        root.muted = newMuted;
        root.osdVisible = true;
        hideTimer.restart();
    }

    Timer {
        id: hideTimer
        interval: 1500
        onTriggered: root.osdVisible = false
    }

    // ---- volume / mic: Pipewire push ----
    readonly property var trackedNodes: {
        const arr = [];
        if (Pipewire.defaultAudioSink) arr.push(Pipewire.defaultAudioSink);
        if (Pipewire.defaultAudioSource) arr.push(Pipewire.defaultAudioSource);
        return arr;
    }
    PwObjectTracker { objects: root.trackedNodes }

    readonly property real sinkVolume: Pipewire.defaultAudioSink && Pipewire.defaultAudioSink.audio ? Pipewire.defaultAudioSink.audio.volume : 0
    readonly property bool sinkMuted: Pipewire.defaultAudioSink && Pipewire.defaultAudioSink.audio ? Pipewire.defaultAudioSink.audio.muted : false
    readonly property real sourceVolume: Pipewire.defaultAudioSource && Pipewire.defaultAudioSource.audio ? Pipewire.defaultAudioSource.audio.volume : 0
    readonly property bool sourceMuted: Pipewire.defaultAudioSource && Pipewire.defaultAudioSource.audio ? Pipewire.defaultAudioSource.audio.muted : false

    onSinkVolumeChanged: root.show("volume", sinkVolume, sinkMuted)
    onSinkMutedChanged: root.show("volume", sinkVolume, sinkMuted)
    // Mic volume is scroll-adjustable too (AudioInput.qml's own
    // MouseArea.onWheel, pre-existing, not something added this pass) --
    // missed wiring this one up alongside the mute handler below at
    // first, so scrolling changed the level but never popped the OSD.
    onSourceVolumeChanged: root.show("mic", sourceVolume, sourceMuted)
    onSourceMutedChanged: root.show("mic", sourceVolume, sourceMuted)

    // ---- brightness: IPC-poked, one-shot sysfs read ----
    // ---- output device type -------------------------------------------
    // Which kind of device the default sink plays through, and the glyph
    // for it. Lived in AudioOutput.qml, one copy per bar -- so one
    // `pactl subscribe` per monitor -- and the volume popup never used it,
    // showing a speaker while the bar showed headphones. One copy here,
    // read by both.
    // Port *key* (e.g. "analog-output-headphones"), not the human label --
    // the label is locale-dependent (French here: "Casque audio") and
    // wouldn't match an English regex anyway. The key is stable.
    property string activePort: ""
    readonly property bool isHeadphone: /headphones?|headset|earbuds/i.test(root.activePort)
    readonly property bool isHdmi: /hdmi|displayport/i.test(root.activePort)

    function refreshActivePort() {
        // Already querying from earlier in the same burst -- come back
        // in a moment instead of dropping this refresh on the floor.
        // The LAST event of a burst is the one carrying the settled
        // state, so silently skipping it (which is what the old
        // call-site `!portQuery.running` guard did) is exactly the wrong
        // one to lose.
        if (portQuery.running) { portDebounce.restart(); return; }
        portQuery.running = true;
    }

    // LC_ALL=C is NOT optional here, and leaving it off was a real bug:
    // this process inherits the session's LANG (fr_FR.UTF-8 on this
    // machine) and `pactl subscribe` TRANSLATES its event lines --
    //     C  : Event 'change' on sink #67
    //     fr : Événement « changement » sur destination #67
    // -- so the English "sink" the filter below looks for never appeared
    // in the stream at all. No event ever matched, nothing ever
    // re-queried, and `activePort` kept whatever the single
    // Component.onCompleted query had set at startup: plug headphones in
    // after the bar is up and the speaker glyph stayed forever.
    // `portQuery` below had the export from the start (its awk matches
    // the literal "Name:"/"Active Port:" keys, just as locale-sensitive);
    // this half simply never got it. `exec` so the bash wrapper replaces
    // itself with pactl rather than lingering as a second process for
    // the whole lifetime of the bar.
    Process {
        id: portWatcher
        command: ["bash", "-c", "export LC_ALL=C; exec pactl subscribe"]
        running: true
        stdout: SplitParser {
            splitMarker: "\n"
            // Anchored on " on <type> #" instead of a bare substring
            // test: "sink" on its own also matches `sink-input`, which
            // fires on every stream start/stop and every per-app volume
            // tick -- orders of magnitude more traffic than anything
            // that can actually move the sink's own port, all of it
            // re-querying for nothing.
            //
            // `card` sits in the list next to `sink` because on this
            // machine's combo jack, physically plugging headphones in is
            // a CARD event (that is where port availability lives) as
            // much as a sink one -- verified live, `pactl subscribe`
            // prints both. Matching only `sink` would be relying on luck
            // rather than on the event that describes the change.
            onRead: (line) => {
                if (/ on (sink|card|server) #/.test(line)) portDebounce.restart();
            }
        }
    }

    // Coalesces bursts. The old `!portQuery.running` guard only stopped
    // two queries from OVERLAPPING -- it did nothing about rate, and a
    // single volume scroll on this very module emits a run of sink+card
    // events, each of which would otherwise spawn its own `bash` +
    // `pactl list sinks`. That cost was never actually paid before (see
    // the locale bug above: nothing matched, so nothing ran), which is
    // exactly why it would have landed as a fresh regression the moment
    // the filter started working. 180ms is far under "instant" for a
    // jack you just plugged in, and long enough to swallow a scroll
    // step's worth of events.
    Timer {
        id: portDebounce
        interval: 180
        repeat: false
        onTriggered: root.refreshActivePort()
    }

    Process {
        id: portQuery
        command: ["bash", "-c",
            "export LC_ALL=C; sink=$(pactl get-default-sink); pactl list sinks | " +
            "awk -v s=\"$sink\" '$1==\"Name:\" && $2==s {f=1} f && /Active Port:/ {print $3; f=0}'"]
        stdout: StdioCollector {
            onStreamFinished: root.activePort = this.text.trim()
        }
    }

    Component.onCompleted: root.refreshActivePort()

    // Bluetooth comes from the node itself: a bluez sink is named
    // "bluez_output...", while its ports are the same headphone/speaker
    // keys a wired one uses.
    readonly property bool outputIsBluetooth: !!Pipewire.defaultAudioSink
        && /^bluez/i.test(Pipewire.defaultAudioSink.name || "")

    // MingCute: volume_off / headphone / computer (HDMI, DisplayPort) /
    // bluetooth (a Bluetooth sink that is not a headset: a speaker) /
    // volume. Headphones win over Bluetooth -- a Bluetooth headset is
    // still headphones, and says so through its port.
    readonly property string outputGlyph: {
        if (root.sinkMuted) return "\uF584";
        if (root.isHeadphone) return "\uEF0A";
        if (root.isHdmi) return "\uEC04";
        if (root.outputIsBluetooth) return "\uEA40";
        return "\uF580";
    }

    property string backlightPath: ""
    property int maxBrightness: 1

    // hwmon-style glob discovery, same one-time-at-startup shape
    // SystemStats.qml's fanDiscover uses -- the backlight device name
    // (e.g. "intel_backlight", "amdgpu_bl0") isn't stable across
    // machines either.
    Process {
        id: backlightDiscover
        command: ["bash", "-c", "find /sys/class/backlight -mindepth 1 -maxdepth 1 2>/dev/null | head -n1"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                root.backlightPath = this.text.trim();
                if (root.backlightPath !== "") {
                    maxFile.path = root.backlightPath + "/max_brightness";
                    curFile.path = root.backlightPath + "/brightness";
                    maxFile.reload();
                    const m = parseInt(maxFile.text().trim());
                    root.maxBrightness = (isNaN(m) || m <= 0) ? 1 : m;
                }
            }
        }
    }
    FileView { id: maxFile; blockLoading: true }
    FileView { id: curFile; blockLoading: true }

    // The backlight level, 0-1, kept here for anything that shows it
    // outside the popup -- Balise's screen row reads and sets it. Updated
    // by readBrightness() (the one-shot sysfs read the popup always used)
    // and optimistically by setBrightness().
    property real brightness: 0

    function readBrightness() {
        if (root.backlightPath === "") return false;
        // reload() alone queues an async re-read -- text() right after
        // still returns the PREVIOUS content (found by testing: showed
        // the pre-brightnessctl value every time). waitForJob() blocks
        // until that queued read actually lands. blockLoading only
        // covers the FIRST load triggered by setting `path`, not
        // explicit reload() calls after that.
        curFile.reload();
        curFile.waitForJob();
        const v = parseInt(curFile.text().trim());
        if (isNaN(v)) return false;
        root.brightness = Math.max(0, Math.min(1, v / root.maxBrightness));
        return true;
    }

    function pokeBrightness() {
        if (!root.readBrightness()) return;
        root.show("brightness", root.brightness, false);
    }

    // Set the backlight from a drag or a wheel in Balise. No popup: the
    // gauge being dragged already shows the level. brightnessctl, the same
    // tool keybinds.lua drives; one call in flight at a time -- a drag
    // fires far faster than a process can spawn, so while one runs only
    // the latest wanted value is kept and sent when it exits. Floored at
    // 1%: 0 turns this panel's backlight fully off.
    property real pendingBrightness: -1
    function setBrightness(frac) {
        const f = Math.max(0.01, Math.min(1, frac));
        root.brightness = f;
        if (brightnessProc.running) {
            root.pendingBrightness = f;
            return;
        }
        brightnessProc.command = ["brightnessctl", "-q", "set", Math.round(f * 100) + "%"];
        brightnessProc.running = true;
    }
    Process {
        id: brightnessProc
        onExited: {
            if (root.pendingBrightness >= 0) {
                const f = root.pendingBrightness;
                root.pendingBrightness = -1;
                root.setBrightness(f);
            }
        }
    }
}
