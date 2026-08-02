import QtQuick
import Quickshell
import Quickshell.Services.UPower

// Native port of waybar/scripts/performance.sh's *status* display.
// Zero exec, zero poll: PowerProfiles.profile is DBus-signal-backed
// (net.hadess.PowerProfiles / power-profiles-daemon), same service
// powerprofilesctl talks to. The click action still shells out to
// generate the roue wheel and launch it (roue-gen + roue), unchanged
// -- that's a one-shot user action, not a status read, no reason to
// touch it.

Item {
    id: root

    // Single glyph always -- floor mostly guards against tiny font-metric
    // jitter between the three icons, not a real digit-count concern.
    // Tighter padding: glued right up against the power button next to it.
    implicitWidth: Math.max(label.implicitWidth + 12, 32)
    implicitHeight: 24

    function iconFor(p) {
        if (p === PowerProfile.Performance) return "󰈸";
        if (p === PowerProfile.PowerSaver) return "󰂏";
        return "󰗑";
    }

    function colorFor(p) {
        if (p === PowerProfile.Performance) return "#ff6e6e";
        if (p === PowerProfile.PowerSaver) return "#237823";
        return "#4fefff";
    }

    Text {
        renderType: Text.NativeRendering
        font.hintingPreference: Font.PreferNoHinting
        id: label
        anchors.centerIn: parent
        text: root.iconFor(PowerProfiles.profile)
        color: root.colorFor(PowerProfiles.profile)
        font.family: "JetBrains Mono"
        font.pixelSize: 13
    }

    MouseArea {
        anchors.fill: parent
        onClicked: Quickshell.execDetached(["bash", "-c",
            "$HOME/.config/waybar/scripts/performance.sh roue-gen && $HOME/.local/bin/roue powerprofile"])
    }
}
