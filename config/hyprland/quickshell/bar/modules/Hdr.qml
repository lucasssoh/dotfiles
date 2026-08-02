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
// HDR *capability* (does this screen's EDID even advertise HDR support)
// IS replicated now, unlike before -- same edid-decode-based check
// hdr.sh's own hdr_capable() does, run once per monitor (a one-shot
// Process at startup / whenever `monitor` changes, not a poll -- this
// is a static hardware property, it doesn't change at runtime). On a
// non-capable screen the badge renders in its normal "off" styling with
// a diagonal strike across it, instead of looking like a normal
// clickable-but-currently-off toggle.
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
// Compact badge instead of a sliding switch: static "hdr" label,
// background flips from neutral to accent2 when active. 4px radius
// matches Block.qml's own corner rounding -- this reads as a flat tag
// that belongs to the block's styling, not a separately-rounded pill
// competing with it.

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
    readonly property string monitorName: root.monitor ? root.monitor.name : ""

    // Optimistic default, matches hdr.sh's own hdr_capable(): if the
    // EDID can't be found or edid-decode isn't installed, don't block --
    // assume capable rather than incorrectly cross out a screen that
    // might well support HDR.
    property bool hdrCapable: true

    // 4px margin around the badge each side (was 2px) -- more breathing
    // room within the item, matching the disc's own margin bump.
    implicitWidth: 40
    implicitHeight: 24

    function refresh() { Hyprland.refreshMonitors(); }

    Component.onCompleted: {
        refresh();
        checkCapability();
    }
    Connections {
        target: Hyprland
        function onRawEvent(event) { root.refresh(); }
    }

    onMonitorNameChanged: checkCapability()

    function checkCapability() {
        if (root.monitorName === "") return;
        capProc.command = ["bash", "-c",
            "edid=\"\"; for p in /sys/class/drm/*-" + root.monitorName + "/edid; do " +
            "[ -e \"$p\" ] && { edid=\"$p\"; break; }; done; " +
            "if [ -n \"$edid\" ] && command -v edid-decode >/dev/null 2>&1; then " +
            "edid-decode \"$edid\" 2>/dev/null | grep -qiE 'HDR Static Metadata|SMPTE ST ?2084|ST2084' " +
            "&& echo 1 || echo 0; " +
            "else echo 1; fi"];
        capProc.running = true;
    }

    Process {
        id: capProc
        stdout: StdioCollector {
            onStreamFinished: root.hdrCapable = this.text.trim() !== "0"
        }
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

    Rectangle {
        id: badge
        anchors.centerIn: parent
        width: 35
        height: 18
        radius: 2
        // Not capable -> always the "off" look, capability isn't
        // something a click can fix so there's no reason to ever tint
        // it as active.
        color: (root.hdrActive && root.hdrCapable) ? "#4fefff" : "#2c2c2e"
        Behavior on color { ColorAnimation { duration: 200 } }

        Text {
            renderType: Text.NativeRendering
            font.hintingPreference: Font.PreferNoHinting
            anchors.centerIn: parent
            text: "hdr"
            color: (root.hdrActive && root.hdrCapable) ? "#141414" : "#f2f2f7"
            font.family: Fonts.ui
            font.pixelSize: 11
            font.bold: true
            Behavior on color { ColorAnimation { duration: 200 } }
        }

        // Diagonal strike across the badge when this screen's EDID
        // doesn't advertise HDR support at all.
        Rectangle {
            visible: !root.hdrCapable
            anchors.centerIn: parent
            width: Math.sqrt(badge.width * badge.width + badge.height * badge.height)
            height: 1
            color: "#636366"   // colors.lua "muted" -- greyed out instead of full white
            rotation: Math.atan2(badge.height, badge.width) * 180 / Math.PI
        }
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
