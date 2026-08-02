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

    readonly property var knownApps: [
        { pattern: /steam/i, icon: "󰓓" },
        { pattern: /lutris/i, image: "../assets/lutris.svg" },
        { pattern: /heroic/i, image: "../assets/heroic.svg" },
        { pattern: /discord/i, icon: "󰙯" },
        { pattern: /vesktop/i, icon: "󰙯" }
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
                        address: t.address
                    });
                    break;
                }
            }
        }
        return out;
    }

    implicitWidth: row.implicitWidth
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
                radius: 4
                color: "#2c2c2e"

                Text {
                    renderType: Text.NativeRendering
                    font.hintingPreference: Font.PreferNoHinting
                    anchors.centerIn: parent
                    visible: chip.modelData.image === ""
                    text: chip.modelData.icon
                    color: "#f2f2f7"
                    font.family: Fonts.icon
                    font.pixelSize: 12
                }

                Image {
                    anchors.centerIn: parent
                    visible: chip.modelData.image !== ""
                    source: chip.modelData.image
                    width: 14
                    height: 14
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
