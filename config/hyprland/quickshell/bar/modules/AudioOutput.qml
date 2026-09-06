import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire
import "../theme"

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

    implicitWidth: label.implicitWidth + 2   // tight fit, no floor -- same fix Battery.qml got, TOOLS' icon-only modules don't need METRICS' square-pill padding
    implicitHeight: 24
    visible: root.node !== null

    // ph-speaker-x / ph-headphones / ph-monitor (no dedicated "hdmi"
    // glyph in Phosphor -- monitor/display is the closest stand-in for
    // "audio routed to the screen's own output") / ph-speaker-high
    readonly property string iconGlyph: root.muted ? ""
        : (root.isHeadphone ? "" : root.isHdmi ? "" : "")
    // Icon ONLY -- the numeric level that used to sit before it is gone,
    // asked for: "puisqu'on a deja ce retour, enleve les valeurs devant
    // les icones audio output et input". That retour is the OSD (Osd.qml,
    // bottom-center), which pops up on exactly the gestures that change
    // this value -- the scroll handler below, and the media keys in
    // keybinds.lua -- so the permanent readout was spelling out a number
    // that is only ever looked at in the moment it is already being shown,
    // larger, somewhere else. The icon still carries what stays true
    // between those moments: the output route (speaker/headphones/HDMI)
    // and mute.
    //
    // The Row is kept around its single remaining child rather than
    // anchoring that Text directly, so `label.implicitWidth` above still
    // measures the same thing and this file stays structurally identical
    // to AudioInput.qml next to it.
    //
    // No color rule for #pulseaudio.output in waybar/style.css -- only
    // the glyph changes on mute, color stays plain text.
    Row {
        id: label
        anchors.centerIn: parent

        // Phosphor vs Inter: box-centering (anchors.verticalCenter) is
        // what measured aligned for Phosphor -- see Temperature.qml's
        // comment for the full reasoning/history.
        Text {
            renderType: Text.NativeRendering
            font.hintingPreference: Font.PreferNoHinting
            anchors.verticalCenter: parent.verticalCenter
            text: root.iconGlyph
            color: "#f2f2f7"
            font.family: Fonts.iconPhosphor
            font.pixelSize: 15
        }
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
            // Capped at 1.0 (100%), not 1.5 -- the boost headroom went
            // unused and asked to come out, same cap as the media-key
            // bind in keybinds.lua now uses.
            root.node.audio.volume = Math.max(0, Math.min(1.0, root.node.audio.volume + step));
        }
    }
}
