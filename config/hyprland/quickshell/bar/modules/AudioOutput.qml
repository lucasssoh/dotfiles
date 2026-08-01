import QtQuick
import Quickshell
import Quickshell.Services.Pipewire

// Native port of waybar's `pulseaudio#output`. Zero exec, zero poll:
// Pipewire.defaultAudioSink is a live DBus/pipewire-backed reference,
// PwObjectTracker keeps its `audio` (volume/muted) sub-properties bound
// and reactive. wpctl/pactl are gone entirely for *display*; audio.sh
// is still used for the actual device-switching click (that's a
// one-shot user action, not something worth reimplementing here).

Item {
    id: root

    readonly property var node: Pipewire.defaultAudioSink
    readonly property real volume: node && node.audio ? node.audio.volume : 0
    readonly property bool muted: node && node.audio ? node.audio.muted : false

    PwObjectTracker {
        objects: root.node ? [root.node] : []
    }

    implicitWidth: Math.max(label.implicitWidth + 20, 65)
    implicitHeight: 24
    visible: root.node !== null

    Text {
        id: label
        anchors.centerIn: parent
        text: root.muted ? "󰖁 " : "󰕾 " + Math.round(root.volume * 100) + "%"
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
                Quickshell.execDetached(["bash", "-c", "$HOME/.config/waybar/scripts/audio.sh output"]);
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
