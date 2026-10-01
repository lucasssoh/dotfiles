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
    // without it the last mark sits flush against the block's own right
    // edge.
    implicitWidth: row.implicitWidth + 8
    implicitHeight: 24

    Row {
        id: row
        anchors.verticalCenter: parent.verticalCenter
        spacing: 6

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

            // The page-indicator layout (2026-09-29): no digits, like a
            // phone's home-screen dots. The active workspace is a long
            // cream bar, every other one a dot, cream if occupied, grey if
            // empty -- you read your place in the row, not a number. The digits and
            // the filled active pill before it were one more thing to read
            // on the island; a solid capsule had already been judged too
            // loud there ("quelque chose de moins contrasté").
            delegate: Item {
                id: pill
                required property var modelData

                // Three states: active (current on THIS monitor -- `active`,
                // not `focused`, which would leave a non-focused monitor's
                // bar with nothing lit), occupied, empty -- and the active
                // one drawn hollow when it holds no window.
                //
                // Occupancy is Hyprland's own per-workspace window count
                // (`lastIpcObject.windows`), re-read by shell.qml's
                // refreshWorkspaces() on every raw IPC event. Not
                // `toplevels`: Quickshell only ever drops a toplevel on a
                // `closewindow` event, and refreshToplevels() adds but
                // never removes -- an XWayland popup (Filius's "win5")
                // whose closewindow never arrived stayed a ghost there,
                // keeping its workspace lit while Hyprland reported 0.
                readonly property bool hasWindows:
                    !!modelData.lastIpcObject && modelData.lastIpcObject.windows > 0
                readonly property bool occupied: !modelData.active && pill.hasWindows

                width: mark.width
                height: 24
                anchors.verticalCenter: parent.verticalCenter

                Rectangle {
                    id: mark
                    anchors.verticalCenter: parent.verticalCenter
                    // Two sizes only -- the active one's bar, everyone
                    // else's dot. Occupied vs empty is already the colour
                    // (cream / grey); a third, mid-length bar for occupied
                    // said it twice.
                    width: pill.modelData.active ? 22 : 5
                    height: 5
                    radius: 2.5
                    // The active workspace with nothing in it is the same
                    // long bar, hollow: you are here, and here is empty.
                    readonly property bool hollow: pill.modelData.active && !pill.hasWindows
                    color: mark.hollow ? "transparent"
                        : (pill.modelData.active ? DrawerTheme.cream
                        : (pill.occupied ? DrawerTheme.cream2 : Ink.faint))
                    border.width: mark.hollow ? 1.2 : 0
                    border.color: DrawerTheme.cream
                    // The bar stretching into place on a workspace switch.
                    // Rare (workspace changes only): a one-off burst, not a
                    // recurring cost.
                    Behavior on width { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                    Behavior on color { ColorAnimation { duration: 180 } }
                }

                MouseArea {
                    cursorShape: Qt.PointingHandCursor
                    // A 5px dot is too small to aim at: the hit area takes
                    // half the gap on each side, so the row is clickable
                    // edge to edge.
                    anchors.fill: parent
                    anchors.leftMargin: -row.spacing / 2
                    anchors.rightMargin: -row.spacing / 2
                    // Hyprland.dispatch() sends the raw request string
                    // over Quickshell's own internal Hyprland IPC path,
                    // which this Hyprland build's custom Lua config
                    // doesn't understand (see hdr.sh's "non-legacy
                    // parser" comments) -- so this bypasses it entirely
                    // via `hyprctl eval`, same as everything else in this
                    // repo: hl.dsp.focus({workspace=...}) wrapped in
                    // hl.dispatch(...), as in hypr/keybinds.lua.
                    onClicked: Quickshell.execDetached(["hyprctl", "eval",
                        "hl.dispatch(hl.dsp.focus({ workspace = \"" + pill.modelData.id + "\" }))"])
                }
            }
        }
    }
}
