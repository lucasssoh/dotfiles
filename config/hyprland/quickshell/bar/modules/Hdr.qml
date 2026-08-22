import QtQuick
import QtQuick.Shapes
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
// background flips from neutral to accent when active. 6px radius
// matches every other 18px-tall pill in this bar (workspace pill,
// ActiveWindow's app chip) -- one shared corner treatment for anything
// at that height, distinct from Block.qml's own (taller, 24px) radius.

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
        radius: 6   // 2 -> 6, matches the workspace pill/window chip rounding
        clip: true
        // Base/off fill -- same muted grey for both "not capable" and
        // "capable but currently SDR", unchanged from before. The active
        // state no longer tints THIS rectangle at all -- see the rainbow
        // overlay below.
        color: "#34383f"

        // Diagonal grey wash instead of a flat accent fill when HDR is
        // actually active on THIS screen, asked for (a rainbow pass came
        // first, then got toned all the way down to grayscale -- same
        // "signifier, not a flat UI accent" instinct, just monochrome
        // now). Plain Rectangle.gradient only does horizontal/vertical --
        // Shape+ShapePath's LinearGradient takes real x1/y1/x2/y2 points,
        // which is what an actual diagonal needs. PathRectangle (not a
        // plain rectangular path) carries its own radius, matching
        // badge's -- same reason the rainbow pass needed `radius:
        // parent.radius` on its overlay: `clip: true` above only clips to
        // badge's bounding RECT, not its rounded silhouette, so an
        // unrounded fill here would square the corners off again. Faded
        // in/out via opacity, not visible:, so it crossfades instead of
        // snapping in.
        // Material tried a few times now (see git history: brushed cyan
        // metal, glossy porcelain) -- frosted glass this round. What
        // actually reads as "frosted" rather than "polished": no crisp
        // specular streak (a sharp highlight band implies a hard
        // reflective surface, the opposite of a diffusing one) -- the 4
        // stops stay close together, cool, and pale instead of swinging
        // dark<->bright. The Shape itself also backs off full opacity
        // (0.82, not 1) when active, so a sliver of badge's own dark base
        // fill still shows through underneath -- a real translucency cue,
        // not just a lighter color.
        Shape {
            anchors.fill: parent
            antialiasing: true
            opacity: (root.hdrActive && root.hdrCapable) ? 0.82 : 0
            Behavior on opacity { NumberAnimation { duration: 250 } }

            ShapePath {
                strokeWidth: -1
                fillGradient: LinearGradient {
                    x1: 0; y1: 0
                    x2: badge.width; y2: badge.height
                    GradientStop { position: 0.0;  color: "#d4dfe0" }
                    GradientStop { position: 0.45; color: "#eef4f4" }
                    GradientStop { position: 0.6;  color: "#c2ced0" }
                    GradientStop { position: 1.0;  color: "#dde6e7" }
                }
                PathRectangle {
                    x: 0; y: 0
                    width: badge.width; height: badge.height
                    radius: badge.radius
                }
            }
        }

        Text {
            renderType: Text.NativeRendering
            font.hintingPreference: Font.PreferNoHinting
            anchors.centerIn: parent
            text: "hdr"
            // Off state: flat light text, unchanged. Active state: cool
            // slate grey (matches the frosted glass's own cool undertone)
            // -- dark enough to hold up against every stop above without
            // going full black, which would look too solid against
            // something meant to read as translucent.
            color: (root.hdrActive && root.hdrCapable) ? "#3a4547" : "#f2f2f7"
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

        // Thin white outline -- only for the active sheen state (asked
        // for: removed again in SDR and "not capable", where there's no
        // jagged Shape curve underneath to clean up in the first place,
        // just badge's own natively-antialiased radius). The sheen
        // Shape's rounded corners (drawn via PathRectangle, not
        // Rectangle's own native radius) came out visibly jaggier than
        // the rest of this bar's curves -- `antialiasing: true` on the
        // Shape above helps some, but a crisp Rectangle-drawn ring on top
        // (Rectangle's own radius IS natively antialiased) is what
        // actually cleans the edge up. Declared LAST so it paints over
        // the sheen underneath.
        Rectangle {
            anchors.fill: parent
            radius: badge.radius
            color: "transparent"
            border.width: (root.hdrActive && root.hdrCapable) ? 1 : 0
            // Always the sheen gradient's own leftmost stop (position 0.0
            // above), so the ring reads as part of the same surface
            // instead of a distinct color choice -- follows it through
            // every material tried here.
            border.color: "#d4dfe0"
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
