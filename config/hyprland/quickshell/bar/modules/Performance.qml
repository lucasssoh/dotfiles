import QtQuick
import Quickshell
import Quickshell.Services.UPower
import "../theme"

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

    // Asked for: a glyph per profile that actually reads as its own
    // state instead of 3 unrelated icons (was a flame, a low-battery
    // glyph, and a plain circle). Same bolt glyph (md-lightning_bolt) for
    // both performance and balanced -- doubled up (two glyphs in one
    // Text, not a real "double bolt" icon -- Material Design Icons
    // doesn't have one) + yellow for performance, single + white for
    // balanced, so the two read as "more/less of the same thing" rather
    // than unrelated symbols. Eco gets its own real leaf glyph.
    function iconFor(p) {
        if (p === PowerProfile.Performance) return "󱐋󱐋";
        if (p === PowerProfile.PowerSaver) return "󰌪";
        return "󱐋";
    }

    function colorFor(p) {
        if (p === PowerProfile.Performance) return "#ffcc00";
        if (p === PowerProfile.PowerSaver) return "#237823";   // colors.lua "play" token -- same green Media.qml's own playing-state disc uses
        return "#f2f2f7";
    }

    Text {
        renderType: Text.NativeRendering
        font.hintingPreference: Font.PreferNoHinting
        id: label
        anchors.centerIn: parent
        text: root.iconFor(PowerProfiles.profile)
        color: root.colorFor(PowerProfiles.profile)
        font.family: Fonts.icon
        font.pixelSize: 13
    }

    MouseArea {
        anchors.fill: parent
        onClicked: Quickshell.execDetached(["bash", "-c",
            "$HOME/.config/waybar/scripts/performance.sh roue-gen && $HOME/.local/bin/roue powerprofile"])
    }
}
