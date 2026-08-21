import QtQuick
import Quickshell.Hyprland
import "../theme"

// Native port of waybar's `hyprland/window` module -- shows both halves
// of its original format ("{initialTitle} · {title}"): app name + what's
// actually running in it. HyprlandToplevel itself only exposes `title`,
// so `initialTitle` is pulled from `activeToplevel.lastIpcObject` (raw
// hyprctl JSON), same escape hatch used elsewhere in this bar
// (workspaceEmpty logic, Hdr.qml's currentFormat). `initialTitle` is a
// long-standing hyprctl clients -j field, but not independently
// re-verified here.
//
// Style: app name sits in a rounded accent "chip" floating on the left
// (like the workspace pill / HDR badge -- 18px tall inset in the 24px
// block). Corner radius matches the active workspace pill exactly (6px)
// -- rounded corners on an otherwise-rectangular chip, not a fully
// rounded pill/stadium shape. The title continues immediately after it
// on the block's own plain background, no gap, no border between them.

Item {
    id: root

    // Which Hyprland monitor this specific bar instance is showing --
    // passed in from shell.qml as Hyprland.monitorFor(bar.screen), same
    // as Workspaces.qml/Hdr.qml. Needed here for the same reason: on a
    // multi-monitor setup, `Hyprland.focusedWorkspace` tracks the
    // workspace of the compositor's globally ACTIVE WINDOW, not "whatever
    // workspace this monitor is currently displaying" -- switching THIS
    // monitor to an empty workspace while another monitor still holds
    // real keyboard focus elsewhere left `focusedWorkspace` pointing at
    // that other, non-empty workspace, so the old focusedWorkspace-based
    // check still showed a stale title here. `monitor.activeWorkspace` is
    // the correct, per-monitor "what's shown right here" property.
    property var monitor: Hyprland.focusedMonitor

    // Hyprland.activeToplevel doesn't reset to null just because you
    // switched to an empty workspace -- it's the last-activated window
    // compositor-wide, and nothing un-activates it when there's nowhere
    // new to activate. Gating on this monitor's own active workspace's
    // toplevels (same live, event-driven model used for the workspace
    // pills' own occupied check -- see Workspaces.qml) catches that case.
    // Floating toplevels (dashboard-fastfetch/dashboard-clock, `no_focus`
    // pinned widgets -- see hypr/windowrules.lua's DASHBOARD block) don't
    // count as "real" content, same convention compact-workspaces.sh and
    // workspace-dashboard.sh already use (excluding floating/dashboard
    // windows from "is this workspace occupied") -- otherwise this bar
    // kept showing that widget's own title/class as if it were the
    // active window.
    readonly property var monitorWs: root.monitor ? root.monitor.activeWorkspace : null
    readonly property bool monitorWsHasRealWindow: {
        if (!root.monitorWs || !root.monitorWs.toplevels) return false;
        const tls = root.monitorWs.toplevels.values;
        for (let i = 0; i < tls.length; i++) {
            const ipc = tls[i].lastIpcObject;
            if (!ipc || !ipc.floating) return true;
        }
        return false;
    }
    readonly property var toplevel: root.monitorWsHasRealWindow ? Hyprland.activeToplevel : null
    readonly property bool hasWindow: root.toplevel !== null

    // Chromium-based browsers (Brave included) already have the active
    // tab's title set as the window title by the time Hyprland captures
    // its mapping-time `initialTitle` snapshot -- unlike most other apps,
    // which still show a generic placeholder at that point (e.g. "kitty"
    // before the shell sets a title). So for Brave, `initialTitle` isn't
    // "Brave", it's whatever the first tab happened to be, frozen there
    // for the window's whole lifetime and never updated on tab switches.
    // `class` is what's actually stable/generic here, so known browser
    // classes get a friendly name derived from it instead of trusting
    // initialTitle.
    readonly property var browserDisplayNames: ({
        "brave-browser": "Brave",
        "firefox": "Firefox",
        "chromium": "Chromium",
        "google-chrome": "Chrome",
    })
    readonly property string appName: {
        if (!root.toplevel) return "";
        const ipc = root.toplevel.lastIpcObject;
        const cls = ipc && ipc.class ? ipc.class : "";
        if (cls && root.browserDisplayNames[cls]) return root.browserDisplayNames[cls];
        return (ipc && ipc.initialTitle) ? ipc.initialTitle : "";
    }
    readonly property string windowTitle: root.toplevel ? root.toplevel.title : ""

    readonly property int maxWidth: 380

    // titleMeasure, not titleLabel.implicitWidth, drives this: titleLabel
    // is anchored right to `parent.right` (root itself), and root's own
    // `width` defaults to `implicitWidth` since nothing sets it
    // explicitly -- reading the constrained/elided titleLabel back into
    // implicitWidth closed a real loop (implicitWidth -> width ->
    // titleLabel.width via the anchor -> elided layout recompute ->
    // titleLabel.implicitWidth -> implicitWidth), harmless in practice
    // but logged a "Binding loop detected" warning once at startup.
    // titleMeasure is a free-standing, invisible, unconstrained Text (same
    // technique Media.qml's own titleMeasure uses) -- its implicitWidth
    // reflects the title's natural width only, never root's own width, so
    // there's nothing left to feed back into.
    implicitWidth: root.hasWindow
        ? Math.min(Math.max(chip.width + titleMeasure.implicitWidth + 26, 120), maxWidth)
        : 0
    // Animated width change, asked for -- title length changes (focus
    // switch, page/tab title update) now widen/narrow this chip smoothly
    // instead of snapping, same duration/curve as Media.qml's own pill.
    // Merged into the left Block now (see shell.qml), so the block and
    // everything after it in that Row follows along for free through the
    // normal implicitWidth binding chain -- no separate Behavior needed
    // anywhere else for this to look smooth.
    Behavior on implicitWidth {
        NumberAnimation { duration: 260; easing.type: Easing.OutCubic }
    }
    implicitHeight: 24
    clip: true

    Text {
        id: titleMeasure
        text: root.windowTitle
        font.family: Fonts.ui
        font.pixelSize: 13
        visible: false
    }

    Rectangle {
        id: chip
        visible: root.hasWindow
        anchors.left: parent.left
        // Small deliberate gap/offset from the block's left edge, purely
        // for breathing room (Block has no border to clear any more).
        anchors.leftMargin: 4
        anchors.verticalCenter: parent.verticalCenter
        width: appLabel.implicitWidth + 22
        height: 18
        radius: 6   // same corner rounding as the active workspace pill (2 -> 6, more pronounced, still not a full pill/stadium shape)
        // No border (see the no-border pass in shell.qml's header
        // comment) -- the graphite-platinum fill against the block's
        // darker background, plus the accent-colored label below, is
        // enough to read as a chip on its own.
        color: "#34383f"

        Text {
            renderType: Text.NativeRendering
            font.hintingPreference: Font.PreferNoHinting
            id: appLabel
            anchors.centerIn: parent
            text: root.appName
            color: "#a8b4c4"
            font.family: Fonts.ui
            font.pixelSize: 13
            font.bold: true
        }
    }

    Text {
        renderType: Text.NativeRendering
        font.hintingPreference: Font.PreferNoHinting
        id: titleLabel
        text: root.windowTitle
        visible: root.hasWindow
        color: "#f2f2f7"
        font.family: Fonts.ui
        font.pixelSize: 13
        anchors.left: chip.right
        anchors.leftMargin: 10
        anchors.right: parent.right
        anchors.rightMargin: 12
        anchors.verticalCenter: parent.verticalCenter
        elide: Text.ElideRight
    }
}
