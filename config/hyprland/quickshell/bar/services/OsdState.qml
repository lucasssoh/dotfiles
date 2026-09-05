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

    function pokeBrightness() {
        if (root.backlightPath === "") return;
        // reload() alone queues an async re-read -- text() right after
        // still returns the PREVIOUS content (found by testing: showed
        // the pre-brightnessctl value every time). waitForJob() blocks
        // until that queued read actually lands. blockLoading only
        // covers the FIRST load triggered by setting `path`, not
        // explicit reload() calls after that.
        curFile.reload();
        curFile.waitForJob();
        const v = parseInt(curFile.text().trim());
        if (isNaN(v)) return;
        root.show("brightness", Math.max(0, Math.min(1, v / root.maxBrightness)), false);
    }
}
