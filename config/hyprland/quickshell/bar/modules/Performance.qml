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

    // Padding only, no floor -- 6px a side, the value ScriptModule and
    // Clock use in this same row. Asked for ("les paddings right de
    // powerprofile et horloge sont trop grand par rapport aux autres").
    //
    // The `Math.max(..., 32)` floor this replaces read as jitter
    // protection but wasn't: Phosphor is monospaced (every glyph advances
    // exactly font.pixelSize), so the width already jumped 32 -> 42
    // whenever the profile went to Performance -- that glyph is TWO
    // characters (see iconFor below) where the other two are one. The
    // floor only ever inflated the SINGLE-glyph cases, i.e. balanced and
    // eco, which is what this module shows nearly all the time, to ~10px
    // of padding a side. Dropping it leaves the same 15px jump on profile
    // change as before, at a consistent 6px a side in every state.
    implicitWidth: label.implicitWidth + 12
    implicitHeight: 24
    // Collapses to nothing without power-profiles-daemon: hasPerformanceProfile
    // is Quickshell's own availability signal for this service (verified
    // against Quickshell.Services.UPower's qmltypes -- there's no separate
    // "daemon present" flag exposed, this is it). Without this gate the
    // module used to always show a "balanced" glyph and silently do
    // nothing on click when the daemon isn't installed/running.
    visible: PowerProfiles.hasPerformanceProfile

    // Asked for: a glyph per profile that actually reads as its own
    // state instead of 3 unrelated icons (was a flame, a low-battery
    // glyph, and a plain circle). Same bolt glyph (md-lightning_bolt) for
    // both performance and balanced -- doubled up (two glyphs in one
    // Text, not a real "double bolt" icon -- Material Design Icons
    // doesn't have one) + yellow for performance, single + white for
    // balanced, so the two read as "more/less of the same thing" rather
    // than unrelated symbols. Eco gets its own real leaf glyph.
    function iconFor(p) {
        if (p === PowerProfile.Performance) return "";
        if (p === PowerProfile.PowerSaver) return "";
        return "";
    }

    function colorFor(p) {
        if (p === PowerProfile.Performance) return "#ffcc00";
        if (p === PowerProfile.PowerSaver) return "#237823";   // colors.lua "play" token -- same green Media.qml's own playing-state disc uses
        return "#f2f2f7";
    }

    // ph-lightning / ph-leaf. Single Text, no adjacent differently-
    // sized text to pair against -- no alignment fix needed here.
    Text {
        renderType: Text.NativeRendering
        font.hintingPreference: Font.PreferNoHinting
        id: label
        anchors.centerIn: parent
        text: root.iconFor(PowerProfiles.profile)
        color: root.colorFor(PowerProfiles.profile)
        font.family: Fonts.iconPhosphorBold
        font.pixelSize: 15
    }

    MouseArea {
        anchors.fill: parent
        onClicked: Quickshell.execDetached(["bash", "-c",
            "$HOME/.config/waybar/scripts/performance.sh roue-gen && $HOME/.local/bin/roue powerprofile"])
    }
}
