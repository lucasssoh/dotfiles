import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire

// Native port of waybar's `pulseaudio#output`. Zero exec, zero poll for
// volume/mute: Pipewire.defaultAudioSink is a live DBus/pipewire-backed
// reference, PwObjectTracker keeps its `audio` sub-properties bound and
// reactive. wpctl/pactl are gone entirely for *that* display; left click
// still shells out to regenerate and open the "audio-output" roue wheel
// (audio.sh roue-gen, one sector per sink -- see waybar/scripts/audio.sh),
// same pattern as Performance.qml's power-profile wheel: a one-shot user
// action, not worth reimplementing, and no separate re-query needed
// afterwards since Pipewire.defaultAudioSink above already picks up the
// change live.
//
// The headphone-vs-speaker icon is the one thing PwNode genuinely can't
// answer: Quickshell.Services.Pipewire exposes no port/route data at all
// (checked the qmltypes -- name/description/nickname only), and on this
// machine's combo jack the SINK's own description never changes between
// "speaker" and "headphone" -- only its active PORT does (analog-output-
// speaker vs analog-output-headphones), which lives one level down, in
// libpulse's port list, not in anything PwNode surfaces. `pactl` is the
// only thing that can see it. Kept event-driven per the "avoid polling"
// rule anyway: `pactl subscribe` is a long-running watcher (same
// watch/query split as StreamModule.qml), a one-shot re-query only runs
// when it actually prints a sink/server change line, never on a clock.
Item {
    id: root

    readonly property var node: Pipewire.defaultAudioSink
    readonly property real volume: node && node.audio ? node.audio.volume : 0
    readonly property bool muted: node && node.audio ? node.audio.muted : false

    // Port *key* (e.g. "analog-output-headphones"), not the human label --
    // the label is locale-dependent (French here: "Casque audio") and
    // wouldn't match an English regex anyway. The key is stable.
    property string activePort: ""
    readonly property bool isHeadphone: /headphones?|headset|earbuds/i.test(root.activePort)
    readonly property bool isHdmi: /hdmi|displayport/i.test(root.activePort)

    function refreshActivePort() { portQuery.running = true; }

    Process {
        id: portWatcher
        command: ["pactl", "subscribe"]
        running: true
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: (line) => {
                if (/sink|server/i.test(line) && !portQuery.running) root.refreshActivePort();
            }
        }
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

    PwObjectTracker {
        objects: root.node ? [root.node] : []
    }

    implicitWidth: Math.max(label.implicitWidth + 20, 65)
    implicitHeight: 24
    visible: root.node !== null

    Text {
        renderType: Text.NativeRendering
        font.hintingPreference: Font.PreferNoHinting
        id: label
        anchors.centerIn: parent
        text: root.muted ? "󰖁 "
            : (root.isHeadphone ? "󰋋 " : root.isHdmi ? "󰡁 " : "󰕾 ") + Math.round(root.volume * 100) + "%"
        // No color rule for #pulseaudio.output in waybar/style.css --
        // only the glyph changes on mute, color stays plain text.
        color: "#f2f2f7"
        font.family: "JetBrains Mono"
        font.pixelSize: 13
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: (mouse) => {
            if (mouse.button === Qt.LeftButton)
                Quickshell.execDetached(["bash", "-c",
                    "$HOME/.config/waybar/scripts/audio.sh roue-gen && $HOME/.local/bin/roue audio-output"]);
            else
                Quickshell.execDetached(["pavucontrol"]);
        }
        onWheel: (wheel) => {
            if (!root.node || !root.node.audio) return;
            const step = wheel.angleDelta.y > 0 ? 0.05 : -0.05;
            root.node.audio.volume = Math.max(0, Math.min(1.5, root.node.audio.volume + step));
        }
    }
}
