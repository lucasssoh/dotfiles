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

    // 380 -> 258: matches Media.qml's own hard cap -- its `openWidth` is
    // max(viewportWidth + 34 + 24, 84) with viewportWidth clamped to
    // maxViewport (200), so 200 + 58 = 258 is the widest mpris' pill ever
    // gets. Asked for: window and mpris (the two "outward growers" in
    // shell.qml's ONE BAR layout) now cap out at the same width.
    readonly property int maxWidth: 258

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
    // Placeholder text/width when there's no active window -- asked for:
    // leaving this at 0 while Media (mpris, the module symmetric to this
    // one across the fixed centerRow -- see shell.qml's ONE BAR) had
    // real content made the bar visibly lopsided, and vice versa. Not
    // meant to look "full", just enough to keep both sides roughly
    // balanced when only one of the two is actually active.
    readonly property string placeholderText: "Super + Space"

    // +30, not +26 any more -- tracks chip's own leftMargin bump below
    // (4 -> 8): 8 (chip left) + 10 (chip->title gap) + 12 (title right
    // pad) = 30.
    implicitWidth: root.hasWindow
        ? Math.min(Math.max(chip.width + titleMeasure.implicitWidth + 30, 120), maxWidth)
        : Math.max(placeholderMeasure.implicitWidth + 24, 92)   // 90 -> 92, point 6: 4pt grid
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
        font.pixelSize: 14
        visible: false
    }

    Text {
        id: placeholderMeasure
        text: root.placeholderText
        font.family: Fonts.ui
        font.pixelSize: 13
        visible: false
    }

    Text {
        renderType: Text.NativeRendering
        font.hintingPreference: Font.PreferNoHinting
        visible: !root.hasWindow
        anchors.centerIn: parent
        text: root.placeholderText
        color: "#636366"   // colors.lua "muted" -- same token Hdr.qml uses for its own greyed-out state
        font.family: Fonts.ui
        font.pixelSize: 13
    }

    Rectangle {
        id: chip
        visible: root.hasWindow
        anchors.left: parent.left
        // Deliberate gap/offset from the block's left edge, purely for
        // breathing room (Block has no border to clear any more). 4 -> 8,
        // asked for -- also keeps the chip clear of the pill's now-bigger
        // bottom-left corner radius (see shell.qml's island Block).
        anchors.leftMargin: 8
        anchors.verticalCenter: parent.verticalCenter
        width: appLabel.implicitWidth + 22
        height: 18
        radius: 6   // same corner rounding as the active workspace pill (2 -> 6, more pronounced, still not a full pill/stadium shape)
        // No FLAT border (see the no-border pass in shell.qml's header
        // comment) -- the graphite-platinum fill against the block's
        // darker background, plus the accent-colored label below, is
        // enough to read as a chip on its own. It does get the same
        // GlassRim "verre métal" edge as the bar's other pills though
        // (asked for): a child, not a sibling, here -- `chip` isn't a
        // Block/reparenting container, so GlassRim's plain-child mode
        // (target left unset, traces `parent`) applies directly.
        color: "#34383f00"

        Text {
            renderType: Text.NativeRendering
            font.hintingPreference: Font.PreferNoHinting
            id: appLabel
            anchors.centerIn: parent
            text: root.appName
            color: "#a8b4c4"
            font.family: Fonts.ui
            font.pixelSize: 14
            font.bold: true
        }

        // Two sources, like metrics/launchers/tools in shell.qml: full-
        // strength topLeft (default) plus a fainter bottomRight one
        // (asked for, extended here from the floating panes to this
        // chip and the active workspace pill).
        GlassRim { cornerRadius: chip.radius }
        GlassRim { cornerRadius: chip.radius; lightOrigin: "bottomRight"; strength: 0.45 }
    }

    Text {
        renderType: Text.NativeRendering
        font.hintingPreference: Font.PreferNoHinting
        id: titleLabel
        text: root.windowTitle
        visible: root.hasWindow
        color: "#f2f2f7"
        font.family: Fonts.ui
        font.pixelSize: 14
        anchors.left: chip.right
        anchors.leftMargin: 10
        anchors.right: parent.right
        anchors.rightMargin: 12
        anchors.verticalCenter: parent.verticalCenter
        elide: Text.ElideRight
    }
}
