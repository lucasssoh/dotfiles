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
    // exactly font.pixelSize), so back when performance was the bolt
    // REPEATED, the width jumped 32 -> 42 on every switch into it -- that
    // state was two characters where the other two were one. The floor
    // only ever inflated the single-glyph cases, i.e. balanced and eco,
    // to ~10px of padding a side. Since each profile got its own glyph
    // (see iconFor below) every state is one character, so there is no
    // jump left at all: a constant 6px a side, always.
    implicitWidth: label.implicitWidth + 12
    implicitHeight: 24
    // Collapses to nothing without power-profiles-daemon: hasPerformanceProfile
    // is Quickshell's own availability signal for this service (verified
    // against Quickshell.Services.UPower's qmltypes -- there's no separate
    // "daemon present" flag exposed, this is it). Without this gate the
    // module used to always show a "balanced" glyph and silently do
    // nothing on click when the daemon isn't installed/running.
    visible: PowerProfiles.hasPerformanceProfile

    // One glyph per profile, each its own symbol: ph-lightning for
    // performance, ph-wind for balanced, ph-leaf for eco. Asked for, and
    // it replaces a scheme where performance and balanced shared the BOLT
    // and were told apart by repeating it -- two glyphs in one Text for
    // performance, one for balanced -- so that "more/less of the same
    // thing" read as a quantity rather than as a mode. Wind says moderate
    // airflow on its own terms and matches the roue wheel, which now uses
    // wind.svg for the same profile (see waybar/scripts/performance.sh).
    //
    // Consequence worth knowing, given the width comment above: all three
    // states are now a SINGLE Phosphor character, and Phosphor is
    // monospaced, so this module's width no longer jumps 15px when the
    // profile changes -- it is constant in every state.
    function iconFor(p) {
        if (p === PowerProfile.Performance) return "\uE2DE";   // ph-lightning
        if (p === PowerProfile.PowerSaver) return "\uE2DA";    // ph-leaf
        return "\uE5D2";                                       // ph-wind (balanced)
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
