import QtQuick
import Quickshell
import Quickshell.Services.Pipewire

// Native port of waybar's `pulseaudio#input` (mic). See AudioOutput.qml.

Item {
    id: root

    readonly property var node: Pipewire.defaultAudioSource
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
        text: root.muted ? "󰍭 ---" : "󰍬 " + Math.round(root.volume * 100) + "%"
        // No color rule for #pulseaudio.input in waybar/style.css either.
        color: "#f2f2f7"
        font.family: "JetBrains Mono"
        font.pixelSize: 13
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: (mouse) => {
            if (mouse.button === Qt.LeftButton)
                Quickshell.execDetached(["bash", "-c", "$HOME/.config/waybar/scripts/audio.sh input"]);
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
