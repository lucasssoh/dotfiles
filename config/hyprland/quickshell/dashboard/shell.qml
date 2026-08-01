import QtQuick
import Quickshell
import Quickshell.Hyprland

// ============================================================
// DASHBOARD — Quickshell replacement for the tty-clock/fastfetch hack
// (scripts/workspace-dashboard.sh + dashboard-clock.sh/dashboard-
// fastfetch.sh + their windowrules in hypr/windowrules.lua). Shows a
// clock + system-info panel on an empty workspace, hides as soon as a
// real (tiled) window appears — same behaviour as the old system, but
// as native layer-shell overlays instead of two wezterm windows tricked
// into looking like widgets.
//
// STATUS: INACTIVE. Nothing in this file runs until "TO ACTIVATE"
// below is done. The old bash+wezterm dashboard (systemd --user
// service) is still what's live today.
//
// API surface used here was checked against the live docs at
// https://quickshell.org/docs/v0.3.0/ (PanelWindow, Quickshell.Io
// Process/StdioCollector, Quickshell.Hyprland, SystemClock) before
// writing — not from memory. Still, this has never been run against a
// real Quickshell binary (not installed on this machine at the time
// of writing) — treat the very first launch as a smoke test, `qs -c
// dashboard` prints QML errors to stderr if a property name has moved
// between versions.
//
// ------------------------------------------------------------
// TO ACTIVATE:
//
// 1. Install Quickshell (Fedora — COPR maintained by errornointernet):
//      sudo dnf copr enable errornointernet/quickshell
//      sudo dnf install quickshell
//
// 2. Symlink this config into ~/.config/quickshell — add "quickshell"
//    to the `modules` array in install.sh (~line 350):
//      modules=("hypr" "waybar" "rofi" "dunst" "swaync" "orbit"
//                "prisme" "roue" "hyprlock" "scripts" "khal" "quickshell")
//    then re-run install.sh (or just symlink by hand:
//      ln -s "$(pwd)/quickshell" ~/.config/quickshell)
//
// 3. Test it manually first, without touching autostart:
//      quickshell -c dashboard
//    Switch to an empty workspace — panels should appear bottom-right
//    (clock) and top-left (system info). Open any tiled window — both
//    should disappear. Ctrl-C to stop.
//
// 4. Retire the OLD dashboard (systemd --user service):
//      systemctl --user disable --now workspace-dashboard.service
//    Then either delete systemd/workspace-dashboard.service from the
//    repo, or install.sh will silently re-enable it on your next
//    `./install.sh` run (it globs every systemd/*.service). Also safe
//    to delete at that point: scripts/workspace-dashboard.sh,
//    hypr/scripts/dashboard-clock.sh, hypr/scripts/dashboard-
//    fastfetch.sh, and the "DASHBOARD" windowrule block in
//    hypr/windowrules.lua (~line 147-175) — harmless if left, since
//    with the service disabled those window classes just never spawn.
//
// 5. Autostart the new one — add to hypr/hyprland.lua, next to the
//    other hl.exec_cmd(...) autostart lines:
//      hl.exec_cmd("quickshell -c dashboard")
// ------------------------------------------------------------

ShellRoot {
    id: root

    // True when the focused workspace has no tiled (non-floating)
    // windows on it. Both panels bind their `visible` to this — single
    // source of truth, single Hyprland listener, instead of one
    // pkill/spawn cycle per widget like the old script.
    property bool workspaceEmpty: false

    function refresh() {
        const ws = Hyprland.focusedWorkspace;
        if (ws === null) {
            workspaceEmpty = false;
            return;
        }
        const tops = Hyprland.toplevels.values;
        for (let i = 0; i < tops.length; i++) {
            const t = tops[i];
            if (!t.workspace || t.workspace.id !== ws.id) continue;
            // lastIpcObject mirrors `hyprctl clients -j` for this
            // client (same field the old bash version parsed) —
            // HyprlandToplevel itself doesn't expose `floating`
            // directly.
            const ipc = t.lastIpcObject;
            if (!ipc || !ipc.floating) {
                workspaceEmpty = false;
                return;
            }
        }
        workspaceEmpty = true;
    }

    Component.onCompleted: refresh()

    // Hyprland.workspaces/toplevels are live bindings, but re-deriving
    // "is this workspace empty" is a loop, not a single property — so
    // it's recomputed explicitly on every IPC event instead of relying
    // on implicit binding tracking through the ObjectModel.
    Connections {
        target: Hyprland
        function onRawEvent(event) { root.refresh(); }
    }

    ClockPanel {
        visible: root.workspaceEmpty
    }

    SysInfoPanel {
        visible: root.workspaceEmpty
    }
}
