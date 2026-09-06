import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

// ============================================================
// DASHBOARD — Quickshell replacement for the tty-clock/fastfetch hack
// (scripts/workspace-dashboard.sh + dashboard-clock.sh/dashboard-
// fastfetch.sh + their windowrules in hypr/windowrules.lua). Shows a
// clock + system-info panel on an empty workspace, hides as soon as a
// real (tiled) window appears — same behaviour as the old system, but
// as native layer-shell overlays instead of two wezterm windows tricked
// into looking like widgets. Fully native now, no terminal involved at
// all: SysInfoPanel.qml gets its fields from `fastfetch --format json`
// (structured data, not the ANSI-art frame), including the logo, which
// is the same rayponce.jpg fastfetch's own config points at, redrawn
// blocky via QML's own Image downsampling instead of chafa.
//
// STATUS: manually verified working (`quickshell -c dashboard`, panels
// correctly show/hide on real vs. empty workspaces, resource use is
// ~140MB RSS / ~0% idle CPU) -- NOT yet autostarted or wired as the
// default (the old bash+wezterm systemd service is still what runs at
// login). See "TO ACTIVATE" below for that last step, whenever wanted.
//
// Toggle without killing the process: `scripts/dashboard-toggle.sh`
// flips the `enabled` gate below over IPC (`qs -c dashboard ipc call
// dashboard toggle`) and notifies via notify-send, which now lands in
// the bar's own notification center (bar/services/NotificationState.qml
// owns org.freedesktop.Notifications; swaync is gone) -- the process
// itself (and its empty-workspace tracking) keeps running either way,
// so toggling is instant and never re-pays the startup cost above.
//
// ------------------------------------------------------------
// TO ACTIVATE (autostart + retire the old system):
//
// 1. Autostart it -- add to hypr/hyprland.lua, next to the other
//    hl.exec_cmd(...) autostart lines:
//      hl.exec_cmd("quickshell -c dashboard")
//
// 2. Retire the OLD dashboard (systemd --user service):
//      systemctl --user disable --now workspace-dashboard.service
//    Then either delete systemd/workspace-dashboard.service from the
//    repo, or install.sh will silently re-enable it on your next
//    `./install.sh` run (it globs every systemd/*.service). Also safe
//    to delete at that point: scripts/workspace-dashboard.sh,
//    hypr/scripts/dashboard-clock.sh, hypr/scripts/dashboard-
//    fastfetch.sh, and the "DASHBOARD" windowrule block in
//    hypr/windowrules.lua (~line 147-175) — harmless if left, since
//    with the service disabled those window classes just never spawn.
// ------------------------------------------------------------

ShellRoot {
    id: root

    // True when the focused workspace has no tiled (non-floating)
    // windows on it. Both panels bind their `visible` to this — single
    // source of truth, single Hyprland listener, instead of one
    // pkill/spawn cycle per widget like the old script.
    property bool workspaceEmpty: false

    // Manual on/off gate, independent of workspaceEmpty -- lets the
    // process stay running permanently (so it's never paying its own
    // startup cost, and the empty-workspace tracking never has a gap)
    // while still being toggleable on demand via `scripts/dashboard-
    // toggle.sh` (SUPER+? or run by hand), same "IPC call flips a
    // property, no process restart" pattern as shell.qml/bar's
    // toggleZen. Starts true: whether that matches what you want at
    // login depends on whether this ends up autostarted (see "TO
    // ACTIVATE" above) -- toggle it once if not.
    property bool enabled: true

    onEnabledChanged: {
        notifyProc.command = ["notify-send", "-a", "Dashboard", "-i",
            "preferences-desktop-screensaver", "Dashboard",
            root.enabled ? "Enabled" : "Disabled"];
        notifyProc.running = true;
    }

    Process { id: notifyProc }

    IpcHandler {
        target: "dashboard"
        function toggle(): void {
            root.enabled = !root.enabled;
        }
    }

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

    // Hyprland.toplevels/.workspaces are async over IPC -- on a fresh
    // launch, this fires before the initial `hyprctl clients/workspaces`
    // round-trip has actually landed (Hyprland.focusedWorkspace still
    // null, or toplevels still empty), so the very first refresh() sees
    // a workspace that only LOOKS empty and both panels show up right
    // away even when they shouldn't. Explicit refreshToplevels() first
    // (same nudge used elsewhere in this repo for Hyprland's own
    // "hl.dispatch doesn't emit IPC events" quirk -- see shell.qml/bar's
    // IpcHandler) plus a short deferred re-check once the socket's
    // initial data has actually had time to arrive.
    Component.onCompleted: {
        Hyprland.refreshWorkspaces();
        Hyprland.refreshToplevels();
        refresh();
    }
    // A single deferred re-check wasn't enough in practice -- how long
    // Hyprland.focusedWorkspace/toplevels take to reflect reality after
    // startup varies (observed anywhere from under a second to several
    // seconds, seemingly depending on how much else the socket has to
    // replay), and refresh() derives its answer entirely from those two
    // properties. Retrying on a short repeating tick for the first few
    // seconds catches it whenever it actually lands, without polling
    // forever -- steady-state updates still come from onRawEvent below.
    Timer {
        interval: 400
        running: true
        repeat: true
        property int ticks: 0
        onTriggered: {
            root.refresh();
            ticks++;
            if (ticks >= 12) running = false;   // ~5s of retries, then stop
        }
    }

    // Hyprland.workspaces/toplevels are live bindings, but re-deriving
    // "is this workspace empty" is a loop, not a single property — so
    // it's recomputed explicitly on every IPC event instead of relying
    // on implicit binding tracking through the ObjectModel.
    Connections {
        target: Hyprland
        function onRawEvent(event) { root.refresh(); }
    }

    ClockPanel {
        visible: root.enabled && root.workspaceEmpty
    }

    SysInfoPanel {
        visible: root.enabled && root.workspaceEmpty
    }
}
