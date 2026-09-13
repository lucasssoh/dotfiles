pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

// HDR state for the whole bar, extracted so the same three lines are not
// written a third time. It started in modules/Hdr.qml (the badge that
// used to sit at the head of the TOOLS row), got copied into
// BaliseHome.qml when the control moved into Balise's SYSTEM block, and
// the "hdr" indicator that replaced the badge in the row would have been
// copy number three. That is exactly the kind of duplicate that drifts:
// three places deciding independently what "HDR is on" means.
//
// See modules/Hdr.qml's own header for the full reasoning this preserves
// -- it is kept in the repo, unreferenced, as that write-up's home. The
// two load-bearing parts:
//
//   * State is read over the already-open Hyprland IPC socket, not by
//     exec'ing anything: refreshMonitors() re-syncs, then the answer is
//     read back out of the monitor's lastIpcObject -- the same
//     "currentFormat" field hdr.sh itself parses with `jq`.
//
//   * The toggle runs hdr.sh as a REAL Process (not execDetached) so
//     refresh() can be called the moment it actually exits. Toggling HDR
//     emits nothing on Hyprland's event socket, which is precisely why
//     the original waybar version needed `pkill -RTMIN+3 waybar` inside
//     hdr.sh's refresh_bar(). `rawEvent` below is kept as a no-cost
//     safety net for real monitor add/remove/resolution changes, but it
//     will NOT catch someone toggling HDR from outside this bar -- known
//     gap, inherited, just now in one place instead of three.
Singleton {
    id: root

    // No `active` property, because there is no single answer: HDR is a
    // per-MONITOR format, and a machine can have one screen in HDR and
    // another not. Callers pass the monitor they are speaking for
    // (`Hyprland.monitorFor(bar.screen)`), the way the badge always did.
    //
    // Still a live binding despite being a function call: QML tracks
    // every property read during a binding's evaluation regardless of
    // call depth, so `monitor.lastIpcObject` below is a real dependency
    // of whatever binds to this, and refresh() re-firing re-evaluates it.
    function activeOn(monitor) {
        const ipc = monitor ? monitor.lastIpcObject : null;
        return !!ipc && typeof ipc.currentFormat === "string"
            && ipc.currentFormat.indexOf("2101010") !== -1;
    }

    function refresh() { Hyprland.refreshMonitors(); }

    // No argument: hdr.sh toggles, it does not take a target state.
    function toggle() { toggleProc.running = true; }

    Component.onCompleted: root.refresh()

    Connections {
        target: Hyprland
        function onRawEvent(event) { root.refresh(); }
    }

    Process {
        id: toggleProc
        command: ["bash", "-c", "$HOME/.config/waybar/scripts/hdr.sh toggle"]
        onExited: root.refresh()
    }
}
