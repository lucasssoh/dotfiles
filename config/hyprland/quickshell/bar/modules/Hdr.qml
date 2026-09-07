import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import "../theme"

// Native-ish port of waybar/scripts/hdr.sh's *status* display: no exec
// at all to read state -- Hyprland.refreshMonitors() re-syncs over the
// already-open Hyprland IPC socket, then the result is read back out
// of lastIpcObject (the same "currentFormat" field hdr.sh itself parses
// via `jq -r .currentFormat`).
//
// HDR *capability* (does this screen's EDID even advertise HDR support,
// same edid-decode-based check hdr.sh's own hdr_capable() does) is NOT
// reflected in the badge at all any more -- tried both a diagonal strike
// and a grey fill for a non-capable screen, neither actually read
// clearly at a glance, so that distinction was dropped rather than kept
// half-legible. The badge always looks the same regardless: transparent
// off, cyan-rimmed active (see badge's own comment below).
//
// Why the refresh is wired the way it is below: toggling HDR (hdr.sh's
// `hyprctl eval "hl.monitor(...)"`) does NOT appear to emit anything on
// Hyprland's IPC event socket -- that's *why* the original waybar
// version needed an explicit `pkill -RTMIN+3 waybar` in hdr.sh's
// refresh_bar() instead of just polling/listening for an event. Since
// hdr.sh isn't being touched (still shared with live waybar), the
// click here runs as a real Process instead of execDetached so
// `refreshMonitors()` can be called the moment the script actually
// exits -- i.e. right after apply() has run, not on a guessed delay.
// `Hyprland.rawEvent` is kept too, as a no-cost safety net for actual
// monitor add/remove/resolution events, but it will NOT catch someone
// toggling HDR from outside this bar (a terminal, hdr.sh's own rofi
// menu run directly, etc.) -- known gap, same one-way-signal
// limitation the original had before this rewrite, just narrower now.
//
// Compact badge instead of a sliding switch: static "hdr" label, always
// on a transparent fill -- active/inactive is signalled by the rim's
// colour, not the badge itself (see its own comment below). Radius is
// 6, the same as every other 18px-tall pill in this bar (workspace
// pill, ActiveWindow's app chip, and BaliseButton's own badge two
// slots to the right in this same `tools` pill).

Item {
    id: root

    // Which Hyprland monitor this specific bar instance is showing --
    // passed in from shell.qml as Hyprland.monitorFor(bar.screen), so
    // each bar's HDR badge reflects ITS OWN screen, not whichever
    // monitor happens to be globally focused. Falls back to
    // focusedMonitor only if nothing was passed in.
    property var monitor: Hyprland.focusedMonitor
    readonly property var ipc: monitor ? monitor.lastIpcObject : null
    readonly property bool hdrActive: ipc && typeof ipc.currentFormat === "string"
        && ipc.currentFormat.indexOf("2101010") !== -1

    // 4px margin around the badge each side (was 2px) -- more breathing
    // room within the item, matching the disc's own margin bump.
    implicitWidth: 40
    implicitHeight: 24

    function refresh() { Hyprland.refreshMonitors(); }

    Component.onCompleted: refresh()
    Connections {
        target: Hyprland
        function onRawEvent(event) { root.refresh(); }
    }

    Process {
        id: toggleProc
        command: ["bash", "-c", "$HOME/.config/waybar/scripts/hdr.sh toggle"]
        onExited: root.refresh()
    }

    Process {
        id: menuProc
        command: ["bash", "-c", "$HOME/.config/waybar/scripts/hdr.sh menu"]
        onExited: root.refresh()
    }

    // Back to ONE look regardless of state (asked for -- both the grey
    // not-capable fill and the porcelain-white active fill are gone):
    // transparent badge, light text, always. Not-capable no longer
    // differs from plain off at all -- it never actually read clearly at
    // a glance either way, so the badge stops trying to signal it (was:
    // a diagonal strike, then a grey fill; both dropped now).
    //
    // Active is still distinguishable, but ONLY via the rim below, not
    // the fill: same transparent badge, but the glass edge's own
    // highlight turns cyan instead of the neutral off-white every other
    // rim in this bar uses -- GlassRim's `highlightColor`, itself
    // Behavior-animated so the whole 5-stop ramp crossfades hue smoothly
    // instead of snapping.
    Rectangle {
        id: badge
        anchors.centerIn: parent
        width: 35
        height: 18
        // 8 -> 6: back to the shared 6 (asked for -- "que les boutons hdr
        // et display de tools island soient comme le bouton de balise,
        // c-a-d avec coin arrondi mais pas totalement arrondi comme un
        // pill"). 8 on an 18px-tall badge sits one pixel short of a full
        // 9px capsule, which is what read as pill-shaped next to
        // BaliseButton's own 6px badge in the same row; nesting closer to
        // concentric with the `tools` pill's 10px left corner is no longer
        // worth the two chips in that row not matching each other.
        radius: 6
        color: "transparent"

        Text {
            renderType: Text.NativeRendering
            font.hintingPreference: Font.PreferNoHinting
            anchors.centerIn: parent
            text: "hdr"
            // Matches the rim's own cyan when active (asked for) -- same
            // hex as `highlightColor` below, so the label and the edge
            // read as the one signal, not two slightly-off cyans.
            color: root.hdrActive ? "#6be3e8" : "#f2f2f7"
            font.family: Fonts.ui
            font.pixelSize: 13
            font.bold: true
            Behavior on color { ColorAnimation { duration: 200 } }
        }
    }

    // Sibling, not child of badge -- same reason GlassRim is kept out of
    // Block's content Row in shell.qml: it traces badge's own x/y/width/
    // height directly and must paint after it to sit on top of the fill.
    // cornerRadius matches badge's own radius (GlassRim defaults to
    // Block's 10px). highlightColor: cyan when HDR is actually active on
    // THIS screen, the rim's own neutral default otherwise -- the ONLY
    // visual difference active/inactive the FILL has left (see badge's
    // own comment above; the label's own colour is the other half, see
    // its Text above).
    //
    // Two sources, like metrics/launchers/tools in shell.qml and
    // ActiveWindow.qml/Workspaces.qml's own pills (asked for, extended
    // here to Hdr too): full-strength topLeft (default) plus a fainter
    // bottomRight one, both retinted together since they share the same
    // `highlightColor` expression.
    GlassRim {
        target: badge
        cornerRadius: badge.radius
        highlightColor: root.hdrActive ? "#6be3e8" : "#e5e5ea"
        Behavior on highlightColor { ColorAnimation { duration: 200 } }
    }
    GlassRim {
        target: badge
        cornerRadius: badge.radius
        lightOrigin: "bottomRight"
        strength: 0.45
        highlightColor: root.hdrActive ? "#6be3e8" : "#e5e5ea"
        Behavior on highlightColor { ColorAnimation { duration: 200 } }
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: (mouse) => {
            if (mouse.button === Qt.LeftButton) toggleProc.running = true;
            else menuProc.running = true;
        }
    }
}
