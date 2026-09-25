pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Hyprland
import "."

// The drawer behind the Launchers chips -- same panelOpen/activeScreen/
// close shape as the four toolsIsland states beside it, hosted by its own
// island (launchersIsland in shell.qml) rather than by TOOLS.
//
// Why it exists at all: a Launchers chip had exactly one action, focus,
// and for an app that hides instead of quitting that is a dead end. Two
// facts, both measured on this machine rather than assumed:
//
//   * ~/.config/discord/settings.json carries no MINIMIZE_TO_TRAY key, so
//     Discord runs with its default (on) -- closing the window HIDES it.
//   * `busctl --user` lists no StatusNotifierWatcher at all. Nothing on
//     this session hosts a tray, so Discord's tray icon never appears and
//     the hidden window has no way back, and no "Quit Discord" menu.
//
// So the window is unreachable and the app unquittable by any route the
// desktop offers -- except this bar, which knows the toplevel is there.
// Hence three actions rather than one, and hence QUIT being a signal to
// the process rather than a window close: closing the window is precisely
// the thing that does not quit these apps.
//
// The pid comes from Hyprland's own client list (`lastIpcObject.pid`,
// already read by Launchers.qml for `.class`) and is the app's MAIN
// process -- verified against Discord: pid 64937 is the Electron browser
// process that owns the Wayland connection, with the zygote/gpu/renderer
// children under it, so SIGTERM there takes the whole tree down the same
// way "Quit" in its own menu would.
Singleton {
    id: root

    // ---------------------------------------------------------------
    // the apps, and which windows they have open
    // ---------------------------------------------------------------
    //
    // Moved here from modules/Launchers.qml when this drawer arrived --
    // the chips and the drawer read the same list, and Launchers is
    // instantiated once per monitor while this is one singleton, so the
    // scan happens once instead of once per screen.

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
        { pattern: /steam/i, label: "Steam", icon: "" },
        { pattern: /lutris/i, label: "Lutris", image: "../assets/lutris.svg" },
        // -2 -> -1: the icon itself shrank (14 -> 11px) since this was
        // tuned, so the same raw offset overshot -- asked for.
        { pattern: /heroic/i, label: "Heroic", image: "../assets/heroic.svg", yOffset: -1 },
        { pattern: /discord/i, label: "Discord", icon: "" },
        { pattern: /vesktop/i, label: "Vesktop", icon: "" }
    ]

    // One chip per known app type (not per window -- if an app has
    // several windows, only the first one found is used as the focus
    // target, same "one icon per app" spirit apps.sh had, just now with
    // something real behind the icon to click on). The LATER windows are
    // not dropped entirely any more: they are counted, because the
    // actions drawer draws a real distinction between closing this one
    // window and quitting the process behind all of them.
    //
    // `pid` rides along for the same drawer -- it is the one field that
    // makes "quit" possible at all, and it costs nothing here: Hyprland
    // already reports it in the same `lastIpcObject` this reads `.class`
    // from, so no /proc walk and no pgrep.
    //
    // `image` is resolved to an absolute URL rather than left as the
    // "../assets/..." string it is written as: a relative source resolves
    // against the FILE it is evaluated in, and this one list is drawn
    // from two directories now (modules/Launchers.qml's chips and
    // modules/launcher/LauncherActions.qml's header), where the same
    // relative string would point at two different places -- one of them
    // nonexistent. Resolved here, against this file, it means the same
    // image everywhere.
    readonly property var matches: {
        const tops = Hyprland.toplevels.values;
        const index = {};
        const out = [];
        for (let i = 0; i < tops.length; i++) {
            const t = tops[i];
            const ipc = t.lastIpcObject;
            if (!ipc || !ipc.class || t.address === "") continue;
            for (let k = 0; k < knownApps.length; k++) {
                if (!knownApps[k].pattern.test(ipc.class)) continue;
                if (index[k] !== undefined) {
                    out[index[k]].windowCount += 1;
                    break;
                }
                index[k] = out.length;
                out.push({
                    label: knownApps[k].label,
                    icon: knownApps[k].icon || "",
                    image: knownApps[k].image ? Qt.resolvedUrl(knownApps[k].image).toString() : "",
                    yOffset: knownApps[k].yOffset || 0,
                    address: t.address,
                    pid: ipc.pid || 0,
                    windowCount: 1
                });
                break;
            }
        }
        return out;
    }

    // ---------------------------------------------------------------
    // open / close
    // ---------------------------------------------------------------

    property bool panelOpen: false
    property var activeScreen: null

    // A COPY of the `matches` entry this panel is about, not a reference
    // into Hyprland.toplevels: that model is rebuilt wholesale on every
    // refreshToplevels(), which the Connections above fires on every IPC
    // event -- so a held reference would go stale or dangle exactly while
    // the panel is open and the user is about to act on it.
    property string label: ""
    property string icon: ""
    property string image: ""
    property int iconYOffset: 0
    property string address: ""
    property int pid: 0
    property int windowCount: 0

    // Set once SIGTERM has been sent, cleared on close. Drives the
    // "Force quit" row: an app that took the signal disappears from
    // Hyprland's client list within a second or two and closes this panel
    // on its own (see syncTarget below), so a target still standing after
    // `escalation` is one that ignored it.
    property bool quitSent: false
    property bool forceOffered: false
    readonly property int escalation: 4000

    function toggleFor(screen, app) {
        if (root.panelOpen && root.address === app.address
            && root.activeScreen === screen) {
            root.close();
            return;
        }
        root.openFor(screen, app);
    }

    // The body toggleFor used to have inline, split out because hover
    // needs the same thing without the toggle: a pointer entering a chip
    // OPENS, it does not flip a switch -- re-entering the chip the panel
    // is already about must leave it exactly as it is, and going through
    // toggleFor would have shut it.
    function openFor(screen, app) {
        hoverOpenTimer.stop();
        hoverCloseTimer.stop();
        root.pendingApp = null;
        // Mutually exclusive with TOOLS' four drawers, same rule they
        // already apply to each other -- see NotificationState.qml. Not
        // for lack of room (this island is its own), but because TOOLS'
        // drawer band extends leftward past its row and would sit on top
        // of this one.
        NotificationState.close();
        BaliseState.close();
        PowerState.close();
        MixerState.close();
        CalendarState.close();

        root.label = app.label;
        root.icon = app.icon;
        root.image = app.image;
        root.iconYOffset = app.yOffset;
        root.address = app.address;
        root.pid = app.pid;
        root.windowCount = app.windowCount;
        root.quitSent = false;
        root.forceOffered = false;
        forceTimer.stop();

        root.activeScreen = screen;
        root.panelOpen = true;
    }

    function close() {
        hoverOpenTimer.stop();
        hoverCloseTimer.stop();
        root.pendingApp = null;
        root.panelOpen = false;
        root.quitSent = false;
        root.forceOffered = false;
        forceTimer.stop();
    }

    // ---------------------------------------------------------------
    // hover
    // ---------------------------------------------------------------
    //
    // Asked for: the drawer opens on a plain hover rather than only on a
    // right click ("un simple hover"). The click paths are untouched --
    // left still focuses, right still toggles -- this is a third way in,
    // and it is the one with all the edge cases, because a pointer is
    // never anywhere on purpose the way a click is.
    //
    // Four of them, and each is a real timer or guard below rather than
    // something hover alone would have got right:
    //
    //   * SWEEPING PAST. The chips sit between the central island and
    //     TOOLS, so the pointer crosses all five of them on its way to
    //     the notification bell. Opening on contact would flash five
    //     panels in half a second, so an entry has to LAST
    //     `hoverOpenDelay` before it counts. Switching chips while the
    //     panel is already open skips that wait -- the decision to have
    //     this open has already been made, and re-running the delay
    //     there would just make the retarget feel broken.
    //
    //   * THE GAP. The drawer is a separate block sitting `drawerTop -
    //     rowHeight` px below the chips (7 on this bar), so travelling
    //     from the chip into the panel means leaving both for a few
    //     frames. Hence `hoverCloseGrace`: leaving arms a close, it does
    //     not perform one, and anything that re-enters (the same chip,
    //     another chip, the panel itself) cancels it.
    //
    //   * THE PANEL ITSELF. LauncherActions has to keep the panel alive
    //     while the pointer is inside it, which is `hoverKeep` -- and it
    //     does that through a HoverHandler rather than a MouseArea
    //     precisely because the action rows underneath still need their
    //     own clicks.
    //
    //   * SOMEBODY ELSE'S DRAWER. openFor() closes the other four, which
    //     is right for a click and hostile for a hover: with the
    //     notification center open, reaching its bell means sweeping over
    //     these chips, and a hover that honoured the exclusion rule would
    //     shut the very panel the user is walking towards. So hover
    //     declines to open at all while another drawer is up. The right
    //     click still gets through -- that one is an actual request.
    readonly property int hoverOpenDelay: 130
    readonly property int hoverCloseGrace: 240

    // The chip a pending open is about. A COPY of the matches entry, same
    // reason the fields above are copies rather than a live reference into
    // Hyprland.toplevels: `matches` is rebuilt on every IPC event, which
    // is to say several times inside a 130ms wait.
    property var pendingApp: null
    property var pendingScreen: null

    function otherDrawerOpen() {
        return NotificationState.centerOpen || BaliseState.panelOpen
            || PowerState.panelOpen || MixerState.panelOpen
            || CalendarState.panelOpen;
    }

    function hoverEnter(screen, app) {
        hoverCloseTimer.stop();
        if (root.otherDrawerOpen()) return;
        // Already open: retarget now, no delay (see SWEEPING PAST above).
        if (root.panelOpen) {
            if (root.address === app.address && root.activeScreen === screen)
                return;
            root.openFor(screen, app);
            return;
        }
        root.pendingScreen = screen;
        root.pendingApp = app;
        hoverOpenTimer.restart();
    }

    function hoverExit() {
        hoverOpenTimer.stop();
        root.pendingApp = null;
        if (root.panelOpen) hoverCloseTimer.restart();
    }

    // The pointer is somewhere that counts as "still on this drawer" --
    // inside the panel, or back on a chip. Cancels a pending close without
    // touching the target.
    function hoverKeep() { hoverCloseTimer.stop(); }

    Timer {
        id: hoverOpenTimer
        interval: root.hoverOpenDelay
        onTriggered: {
            if (!root.pendingApp) return;
            root.openFor(root.pendingScreen, root.pendingApp);
        }
    }

    Timer {
        id: hoverCloseTimer
        interval: root.hoverCloseGrace
        // Not close(): a SIGTERM waiting on its "Force quit" escalation is
        // a conversation in progress, and the pointer drifting off the
        // panel is not the user abandoning it. Every other state closes on
        // its own.
        onTriggered: { if (!root.quitSent) root.close(); }
    }

    Timer {
        id: forceTimer
        interval: root.escalation
        onTriggered: root.forceOffered = true
    }

    // ---------------------------------------------------------------
    // actions
    // ---------------------------------------------------------------
    //
    // Both dispatchers go through the Lua names, not the native ones --
    // hyprland.lua configures this compositor in Lua, so `hyprctl
    // dispatch` evaluates its argument AS LUA and `focuswindow
    // address:0x...` is a parse error, not a dispatch (the full error is
    // quoted in Launchers.qml). `hl.dsp.window.close` is the same call
    // keybinds.lua's SUPER+Q makes.

    function focusWindow() {
        if (root.address === "") return;
        Quickshell.execDetached(["hyprctl", "dispatch",
            "hl.dsp.focus({ window = 'address:" + root.address + "' })"]);
        root.close();
    }

    function closeWindow() {
        if (root.address === "") return;
        Quickshell.execDetached(["hyprctl", "dispatch",
            "hl.dsp.window.close({ window = 'address:" + root.address + "' })"]);
        root.close();
    }

    // SIGTERM, and deliberately NOT chained to a SIGKILL on a sleep: for
    // an Electron app TERM is the graceful path (it runs the same
    // shutdown as the app's own Quit -- settings flushed, session ended),
    // KILL is state loss. So the escalation is offered as a second,
    // explicit click if the first one visibly did nothing, rather than
    // fired behind the user's back a few seconds later.
    function quit() {
        if (root.pid <= 0) return;
        Quickshell.execDetached(["kill", "-TERM", String(root.pid)]);
        root.quitSent = true;
        root.forceOffered = false;
        forceTimer.restart();
    }

    function forceQuit() {
        if (root.pid <= 0) return;
        Quickshell.execDetached(["kill", "-KILL", String(root.pid)]);
        root.close();
    }

    // ---------------------------------------------------------------
    // staying in sync with the window that is actually there
    // ---------------------------------------------------------------
    //
    // The panel is about ONE window, and that window can go away without
    // anything here having asked for it -- the app quit from its own
    // menu, the quit above worked, another toplevel took focus. Leaving
    // the panel up with a dead address means the next click dispatches
    // at nothing (or, worse, at an address Hyprland has since reused).
    //
    // Gated on panelOpen, so this loop runs over ~5 toplevels only while
    // the drawer is actually open and costs nothing the rest of the time
    // -- the same "pay for it while it is on screen" rule PowerState's
    // GetHistory timer follows.
    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (!root.panelOpen) return;
            root.syncTarget();
        }
    }

    function syncTarget() {
        if (root.address === "") return;
        const tops = Hyprland.toplevels.values;
        for (let i = 0; i < tops.length; i++) {
            if (tops[i].address === root.address) return;
        }
        // Gone. If this is the quit landing, the panel closing IS the
        // confirmation; if the user closed the window by other means,
        // there is nothing left for the panel to act on either way.
        root.close();
    }
}
