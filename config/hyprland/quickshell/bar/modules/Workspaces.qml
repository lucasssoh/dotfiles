import QtQuick
import Quickshell
import Quickshell.Hyprland

// Native port of waybar's `hyprland/workspaces` module. No exec, no
// poll: Hyprland.workspaces is a live model kept in sync over the
// Hyprland IPC socket by Quickshell itself.

Item {
    id: root

    // Which Hyprland monitor this specific bar instance is showing --
    // passed in from shell.qml as Hyprland.monitorFor(bar.screen), so
    // each bar (one per connected output, see shell.qml's Variants)
    // shows ITS OWN screen's workspaces, not whichever monitor happens
    // to be globally focused. Falls back to focusedMonitor only if
    // nothing was passed in (shouldn't happen in practice).
    property var monitor: Hyprland.focusedMonitor

    // Row's own implicitHeight is read-only (positioner-computed from
    // children, can't be assigned) -- so the 24px floor lives on this
    // wrapping Item instead, with the Row centered inside it. Without
    // this, the whole module's height is just the tallest pill (18px):
    // fine on its own, but next to 24px siblings (clock, notification)
    // in the same outer Row it reads as "shorter", flush-top with dead
    // space below instead of centered on the same baseline as everyone
    // else.
    // +8 right padding only (Row itself stays left-aligned at x:0) --
    // without it the last workspace number sits flush against the
    // block's own right border.
    implicitWidth: row.implicitWidth + 8
    implicitHeight: 24

    Row {
        id: row
        anchors.verticalCenter: parent.verticalCenter
        spacing: 2

        Repeater {
            // "sorted by id" per Hyprland.workspaces' own docs, but that
            // guarantee apparently only holds for the initial snapshot --
            // workspaces created later (e.g. by workspace-manager.sh
            // reassigning things on a monitor plug/unplug) seem to just
            // get appended in discovery order, not re-sorted into place,
            // which is exactly the "2 before 1, 4 before 1/2/3" the
            // laptop screen was showing. Sorting explicitly here doesn't
            // depend on that guarantee holding at all.
            model: Hyprland.workspaces.values
                .filter(w => w.monitor === root.monitor)
                .sort((a, b) => a.id - b.id)

            delegate: Rectangle {
                id: pill
                required property var modelData

                // `active` = current workspace on ITS OWN monitor;
                // `focused` = that AND the monitor is also the globally
                // focused one. Using `focused` here would mean a bar on
                // a non-focused monitor never highlights anything, even
                // though one of its workspaces genuinely is the active
                // one on that screen -- `active` is the per-monitor-
                // correct one.
                width: modelData.active ? 24 : 18
                height: 18
                anchors.verticalCenter: parent.verticalCenter
                radius: 2
                color: modelData.active ? "#4fefff" : "transparent"

                Text {
                    anchors.centerIn: parent
                    text: modelData.id
                    // waybar/style.css: .active -> @background text on an
                    // @accent2 pill; occupied (not active) -> @text; empty ->
                    // @muted. "occupied" = lastIpcObject.windows > 0 (no
                    // direct HyprlandWorkspace property for window count).
                    color: pill.modelData.active
                        ? "#141414"
                        : ((pill.modelData.lastIpcObject && pill.modelData.lastIpcObject.windows > 0)
                            ? "#f2f2f7" : "#48484a")
                    font.family: "JetBrains Mono"
                    font.pixelSize: 12
                }

                MouseArea {
                    anchors.fill: parent
                    // Hyprland.dispatch() sends the raw request string
                    // over Quickshell's own internal Hyprland IPC path,
                    // which this Hyprland build's custom Lua config
                    // doesn't understand (see hdr.sh's "non-legacy
                    // parser" comments) -- so this bypasses it entirely
                    // via `hyprctl eval`, same as everything else in this
                    // repo. First guess (hl.dispatch("workspace N")) was
                    // wrong too -- the actual working call, straight from
                    // scripts/compact-workspaces.sh:32 and
                    // hypr/keybinds.lua:128, is hl.dsp.focus({workspace=
                    // ...}) wrapped in hl.dispatch(...), not a bare string.
                    onClicked: Quickshell.execDetached(["hyprctl", "eval",
                        "hl.dispatch(hl.dsp.focus({ workspace = \"" + pill.modelData.id + "\" }))"])
                }
            }
        }
    }
}
