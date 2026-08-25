import QtQuick
import Quickshell
import Quickshell.Services.Pipewire
import "../theme"

// Native port of waybar's `pulseaudio#input` (mic). See AudioOutput.qml.
// Left click regenerates and opens the "audio-input" roue wheel
// (audio.sh roue-gen-input, one sector per source -- see
// waybar/scripts/audio.sh), same pattern as AudioOutput.qml's
// audio-output wheel.

Item {
    id: root

    readonly property var node: Pipewire.defaultAudioSource
    readonly property real volume: node && node.audio ? node.audio.volume : 0
    readonly property bool muted: node && node.audio ? node.audio.muted : false

    PwObjectTracker {
        objects: root.node ? [root.node] : []
    }

    implicitWidth: Math.max(label.implicitWidth + 20, 64)   // 65 -> 64, point 6: 4pt grid
    implicitHeight: 24
    visible: root.node !== null

    readonly property string iconGlyph: root.muted ? "" : ""   // ph-microphone-slash / ph-microphone
    readonly property string volumeText: root.muted ? "---" : Math.round(root.volume * 100) + "%"

    // No color rule for #pulseaudio.input in waybar/style.css either.
    Row {
        id: label
        anchors.centerIn: parent
        spacing: 4

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
        Text {
            id: valueLabel
            renderType: Text.NativeRendering
            font.hintingPreference: Font.PreferNoHinting
            anchors.verticalCenter: parent.verticalCenter
            text: root.volumeText
            color: "#f2f2f7"
            font.family: Fonts.ui
            font.pixelSize: 13
        }
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: (mouse) => {
            if (mouse.button === Qt.LeftButton)
                Quickshell.execDetached(["bash", "-c",
                    "$HOME/.config/waybar/scripts/audio.sh roue-gen-input && $HOME/.local/bin/roue audio-input"]);
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
