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

    // Outer breathing room, set per-instance from shell.qml -- see
    // AudioOutput.qml's copy of this pair for the whole reasoning. This
    // is the RIGHT half of that group, so it's `trailingPad` that gets
    // set here and `leadingPad` that stays 0.
    property real leadingPad: 0
    property real trailingPad: 0

    implicitWidth: label.implicitWidth + 2 + root.leadingPad + root.trailingPad   // tight fit, no floor -- same fix Battery.qml got, TOOLS' icon-only modules don't need METRICS' square-pill padding
    implicitHeight: 24
    visible: root.node !== null

    readonly property string iconGlyph: root.muted ? "" : ""   // ph-microphone-slash / ph-microphone
    // Icon ONLY -- see AudioOutput.qml's own note for why the numeric
    // level went away. The "---" this used to show while muted goes with
    // it and loses nothing: the glyph itself already switches to
    // microphone-slash on mute, which is what those dashes stood in for.
    //
    // No color rule for #pulseaudio.input in waybar/style.css either.
    Row {
        id: label
        // Not centerIn: the pads are one-sided. With both at 0 this is
        // x: 1 on a width of implicitWidth+2, i.e. exactly what
        // centerIn resolved to before.
        anchors.verticalCenter: parent.verticalCenter
        x: root.leadingPad + 1

        // Phosphor vs Inter: box-centering (anchors.verticalCenter) is
        // what measured aligned for Phosphor -- see Temperature.qml's
        // comment for the full reasoning/history.
        Text {
            renderType: Text.NativeRendering
            font.hintingPreference: Font.PreferNoHinting
            anchors.verticalCenter: parent.verticalCenter
            text: root.iconGlyph
            color: "#f2f2f7"
            font.family: Fonts.iconPhosphorBold
            font.pixelSize: 15
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
