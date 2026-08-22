import QtQuick
import Quickshell
import Quickshell.Hyprland
import "../theme"

// Native replacement for waybar/scripts/apps.sh: instead of a pgrep-based
// script producing a flat icon string, this reads Hyprland.toplevels
// directly (already live/reactive, zero exec, zero poll) and keeps each
// matched app's window address around -- so unlike apps.sh, every icon
// here is its own clickable chip that raises/focuses that window.
//
// Icons: Steam/Discord/Vesktop keep their existing Nerd Font glyphs
// (real dedicated icons already). Lutris and Heroic Games Launcher
// don't have one -- Simple Icons has both, but Simple Icons isn't part
// of the Nerd Fonts glyph set at all (checked glyphnames.json directly,
// no "si-" prefix present), which is why apps.sh fell back to sharing
// a generic gamepad glyph between them. Real logos instead, as actual
// SVGs (assets/lutris.svg, assets/heroic.svg -- pulled from Simple
// Icons, CC0), rendered as Image rather than Text for those two.
//
// Same lastIpcObject staleness issue Hdr.qml already hit and fixed:
// a toplevel's `lastIpcObject` (needed here for `.class`) doesn't
// update on its own when a new window opens -- it only reflects
// whatever hyprctl reported the last time Hyprland.refreshToplevels()
// was called. Without forcing that refresh, a freshly-launched app's
// class field stays empty/stale until *something else* happens to
// trigger it (a full shell reload re-evaluates everything from
// scratch, which is why that "fixed" it). Same fix as Hdr.qml: force
// a refresh on every Hyprland IPC event.

Item {
    id: root

    function refresh() { Hyprland.refreshToplevels(); }

    Component.onCompleted: refresh()
    Connections {
        target: Hyprland
        function onRawEvent(event) { root.refresh(); }
    }

    // fa-brands steam / fa-brands discord -- kept on Font Awesome
    // Brands rather than moved to Phosphor: Phosphor is a generic UI
    // icon set with no product/protocol logos at all (checked -- no
    // "steam"/"discord" entries), so a real brand mark still needs the
    // one font actually built for that job. Lutris/Heroic stay real SVG
    // assets either way (no font has those logos).
    // `yOffset`: heroic.svg's shield tapers to a point at the bottom --
    // its path bounding box is measured PERFECTLY centered in the 24x24
    // viewBox (checked directly, not eyeballed), yet it still visibly
    // read as sitting low next to the others. That's an optical-
    // centering issue, not a real one: a shape whose "mass" is
    // concentrated toward one end (same idea as the icon-font optical-
    // size passes earlier) needs a small manual nudge to look centered
    // -- the mathematical center isn't the same thing as the perceived
    // one.
    readonly property var knownApps: [
        { pattern: /steam/i, icon: "" },
        { pattern: /lutris/i, image: "../assets/lutris.svg" },
        // -2 -> -1: the icon itself shrank (14 -> 11px) since this was
        // tuned, so the same raw offset overshot -- asked for.
        { pattern: /heroic/i, image: "../assets/heroic.svg", yOffset: -1 },
        { pattern: /discord/i, icon: "" },
        { pattern: /vesktop/i, icon: "" }
    ]

    // One chip per known app type (not per window -- if an app has
    // several windows, only the first one found is used as the focus
    // target, same "one icon per app" spirit apps.sh had, just now with
    // something real behind the icon to click on).
    readonly property var matches: {
        const tops = Hyprland.toplevels.values;
        const seen = [];
        const out = [];
        for (let i = 0; i < tops.length; i++) {
            const t = tops[i];
            const ipc = t.lastIpcObject;
            if (!ipc || !ipc.class || t.address === "") continue;
            for (let k = 0; k < knownApps.length; k++) {
                if (seen.indexOf(k) !== -1) continue;
                if (knownApps[k].pattern.test(ipc.class)) {
                    seen.push(k);
                    out.push({
                        icon: knownApps[k].icon || "",
                        image: knownApps[k].image || "",
                        yOffset: knownApps[k].yOffset || 0,
                        address: t.address
                    });
                    break;
                }
            }
        }
        return out;
    }

    implicitWidth: row.implicitWidth
    // Animated width change, asked for -- even a single chip appearing/
    // disappearing (app opened/closed) now shifts this pill smoothly
    // instead of snapping. Same duration/curve as ActiveWindow.qml's own.
    Behavior on implicitWidth {
        NumberAnimation { duration: 260; easing.type: Easing.OutCubic }
    }
    implicitHeight: 24
    visible: root.matches.length > 0

    Row {
        id: row
        anchors.verticalCenter: parent.verticalCenter
        spacing: 4

        Repeater {
            model: root.matches

            delegate: Rectangle {
                id: chip
                required property var modelData

                width: 22
                height: 22   // was 18 -- more vertical padding around the icon inside the chip
                anchors.verticalCenter: parent.verticalCenter
                radius: 8   // 4 -> 8, matches Block.qml's more pronounced rounding (kept for the hit target's shape, not visible any more)
                // No fill any more -- redundant now that Launchers lives
                // inside the metrics pill (see shell.qml), which already
                // has its own background. Was #34383f, back when each chip
                // sat directly on the bar with no wrapping Block behind it.
                color: "transparent"

                Text {
                    renderType: Text.NativeRendering
                    font.hintingPreference: Font.PreferNoHinting
                    anchors.centerIn: parent
                    visible: chip.modelData.image === ""
                    text: chip.modelData.icon
                    color: "#f2f2f7"
                    font.family: Fonts.iconBrand
                    font.pixelSize: 11   // 13 -> 11, asked for
                }

                Image {
                    anchors.centerIn: parent
                    // yOffset -- see knownApps' own comment: heroic.svg is
                    // mathematically centered in its viewBox but still
                    // reads as sitting low (optical centering, not a real
                    // offset), corrected per-icon rather than guessed here.
                    anchors.verticalCenterOffset: chip.modelData.yOffset
                    visible: chip.modelData.image !== ""
                    source: chip.modelData.image
                    width: 11    // 14 -> 11, same reduction as the Text glyph
                    height: 11
                    // Rasterize straight at the target size instead of
                    // scaling down from the SVG's native resolution --
                    // crisper for a thin-stroke shape like heroic's shield
                    // outline than the blurrier default scaling path.
                    // Tried first as a fix for the droop above, on its own
                    // it wasn't enough (kept anyway, strictly better).
                    sourceSize: Qt.size(width, height)
                    fillMode: Image.PreserveAspectFit
                    smooth: true
                }

                MouseArea {
                    anchors.fill: parent
                    // Plain `hyprctl dispatch`, not the hl.dispatch Lua
                    // detour -- pip-daemon.sh already proves address-
                    // targeted dispatchers (movewindowpixel,
                    // resizewindowpixel) work fine as vanilla hyprctl
                    // dispatch on this system; focuswindow is Hyprland's
                    // own native dispatcher, not part of the custom
                    // hl.dsp.* set, so there's no Lua-quoting quirk to
                    // route around here.
                    onClicked: Quickshell.execDetached(["hyprctl", "dispatch",
                        "focuswindow", "address:" + chip.modelData.address])
                }
            }
        }
    }
}
