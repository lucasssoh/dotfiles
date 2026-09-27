import QtQuick
import Quickshell
import Quickshell.Hyprland
import "../theme"

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
    // block's own right edge.
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

                // Three distinct states, not two: active (current on this
                // monitor), occupied (has windows but not focused right
                // now), empty. The active fill (no border, see the
                // no-border pass in shell.qml's header comment) + bold
                // accent text marks the ONE that matters most -- active --
                // and occupied stays a plain bold number, no decoration:
                // two tiers of emphasis, not two things that both look
                // "highlighted".
                //
                // `toplevels` (this workspace's own live window list, kept
                // in sync via wlr-foreign-toplevel-management -- a Wayland
                // protocol event stream, entirely separate from Hyprland's
                // own IPC socket) is the primary signal, not
                // `lastIpcObject.windows`: that field is just whatever
                // `hyprctl workspaces -j` last reported wholesale, and in
                // practice it was observed to stay stuck at its
                // Quickshell-startup value -- a window opened on workspace
                // 2 well after the bar started kept showing 2 as empty,
                // even right after an explicit Hyprland.refreshWorkspaces()
                // call. `lastIpcObject.windows` is kept as a second,
                // OR'd check rather than dropped outright -- cheap safety
                // net in case toplevels ever comes up empty for some
                // window type (e.g. one that doesn't map to a
                // foreign-toplevel handle).
                readonly property bool occupied: !modelData.active
                    && (
                        (modelData.toplevels && modelData.toplevels.values.length > 0)
                        || (modelData.lastIpcObject && modelData.lastIpcObject.windows > 0)
                    )
                readonly property bool empty: !modelData.active && !pill.occupied

                // `active` = current workspace on ITS OWN monitor;
                // `focused` = that AND the monitor is also the globally
                // focused one. Using `focused` here would mean a bar on
                // a non-focused monitor never highlights anything, even
                // though one of its workspaces genuinely is the active
                // one on that screen -- `active` is the per-monitor-
                // correct one.
                width: modelData.active ? 24 : 18
                // Animated width change, asked for -- the pill visibly
                // growing/shrinking on focus switch instead of snapping.
                // Rare event (only on workspace change), so this is a
                // one-off ~150ms burst, not a recurring cost.
                Behavior on width {
                    NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
                }
                height: 18
                anchors.verticalCenter: parent.verticalCenter
                // The active workspace: a soft veil of the primary ink (18%)
                // behind a semi-bold white digit. It was a solid white
                // capsule with the digit cut out in black for a while (the
                // HyperOS inversion), and read too loud on the black island
                // -- asked for: "quelque chose de moins contrasté". Same veil
                // language as the Balise capsule in the right-hand row.
                radius: height / 2
                color: modelData.active ? Qt.rgba(Ink.primary.r, Ink.primary.g, Ink.primary.b, 0.18) : "transparent"

                Text {
                    visible: !pill.empty
                    renderType: Text.NativeRendering
                    font.hintingPreference: Font.PreferNoHinting
                    anchors.centerIn: parent
                    text: modelData.id
                    // active -> dark ink cut out of the capsule; occupied ->
                    // plain bright text. Empty workspaces draw no digit at
                    // all (the dot below): only the ones holding something
                    // are worth reading.
                    color: Ink.primary
                    font.family: Fonts.ui
                    font.pixelSize: 13
                    font.weight: pill.modelData.active ? Font.DemiBold : Font.Normal
                }

                // Empty workspace: a 4px dot instead of a faint digit, the
                // HyperOS page-indicator idiom. The pill keeps its full
                // width, so the click target does not shrink with it.
                Rectangle {
                    visible: pill.empty
                    anchors.centerIn: parent
                    width: 4
                    height: 4
                    radius: 2
                    color: Ink.faint
                }

                MouseArea {
                    cursorShape: Qt.PointingHandCursor
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
