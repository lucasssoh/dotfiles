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
// The "Net" layout (2026-09-29): where the window lives, in grey, then
// what it is about, in cream -- "nvim  keybinds.lua",
// "Discord  Amis", "12 / 293  Platon-sophiste". The raw title led with
// noise more often than not ("— Mozilla Firefox", "~/code/dotfiles/..."),
// and the app name in front of it said again what the title's tail
// already said. See `parts` for the rules.

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
    // Floating toplevels (pinned widgets, pickers, dialogs) don't count
    // as "real" content -- otherwise this bar kept showing a pinned
    // widget's own title/class as if it were the active window.
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
    //
    // zathura has exactly the same pathology for a different reason: it
    // is never launched as itself here, it is the renderer Liseuse hands
    // a document to (see config/liseuse/), and it sets a real title --
    // "Platon-sophiste.pdf [79/293]" -- before Hyprland takes its
    // snapshot. So `initialTitle` froze a page number into the chip.
    // "Liseuse" is what that window IS from where the user sits.
    readonly property var classDisplayNames: ({
        "brave-browser": "Brave",
        "firefox": "Firefox",
        // Firefox's own Flatpak-style class since it went Wayland-native;
        // unmatched, it fell back to its initialTitle, "Mozilla Firefox".
        "org.mozilla.firefox": "Firefox",
        "org.wezfurlong.wezterm": "wezterm",
        // Nemo's initialTitle is the folder it opened on ("Home").
        "nemo": "Files",
        "chromium": "Chromium",
        "google-chrome": "Chrome",
        "org.pwmt.zathura": "Liseuse",
    })
    // Title tails that name the app in the SYSTEM's language, which the
    // bar does not speak (its text is English): Nemo ends its titles in
    // " - Fichiers" under fr_FR. Matched like the app name, so they go.
    readonly property var classTitleTails: ({
        "nemo": ["fichiers", "files"],
    })
    readonly property string readerClass: "org.pwmt.zathura"
    readonly property string appName: {
        if (!root.toplevel) return "";
        const ipc = root.toplevel.lastIpcObject;
        const cls = ipc && ipc.class ? ipc.class : "";
        if (cls && root.classDisplayNames[cls]) return root.classDisplayNames[cls];
        return (ipc && ipc.initialTitle) ? ipc.initialTitle : "";
    }
    readonly property string windowTitle: root.toplevel ? root.toplevel.title : ""

    // The two halves the row shows: `obj`, what the window is about, and
    // `ctx`, the app it lives in (or, for a document, the page).
    //
    // Rules, first match wins, all plain string work on the live title
    // (no polling, no second source -- it updates with the title):
    //   - the reader (zathura behind Liseuse) titles itself
    //     "<file>.pdf [12/340]": the name without its extension, then the
    //     page, which is the half that changes while you read. The
    //     extension goes because a Markdown document is ALSO a .pdf by the
    //     time zathura sees it (Liseuse renders it first).
    //   - nvim titles itself "<file> (<dir>) - NVIM": the file's basename,
    //     then "nvim" -- the terminal hosting it says nothing useful.
    //   - a title ending in " — <app>" / " - <app>" (Firefox, Discord,
    //     most GTK apps) loses that tail: it is the app name again.
    //   - a title that IS the app name shows once, with no context.
    // Anything else shows as-is, with the app after it.
    function basename(path) {
        return path.replace(/\/+$/, "").split("/").pop();
    }
    readonly property var parts: {
        if (!root.toplevel) return { obj: "", ctx: "" };
        const ipc = root.toplevel.lastIpcObject || {};
        const t = (root.windowTitle || "").trim();
        const app = root.appName;

        if (ipc.class === root.readerClass) {
            const m = t.match(/^(.*?)\s*\[(\d+)\/(\d+)\]\s*$/);
            if (m) return { obj: m[1].replace(/\.[^.]*$/, ""), ctx: m[2] + " / " + m[3] };
        }

        let m = t.match(/^(.+?)(?:\s+\(.*\))?\s+[-–—]\s+NVIM$/i);
        if (m) return { obj: root.basename(m[1].replace(/^[+*]\s*/, "")), ctx: "nvim" };

        const names = [app, ipc.initialTitle || ""].concat(root.classTitleTails[ipc.class] || [])
            .filter(n => n !== "").map(n => n.toLowerCase());
        for (const sep of [" — ", " – ", " - "]) {
            const i = t.lastIndexOf(sep);
            if (i <= 0) continue;
            const tail = t.slice(i + sep.length).toLowerCase();
            if (names.some(n => n === tail || n.endsWith(tail) || tail.endsWith(n)))
                return { obj: t.slice(0, i), ctx: app };
        }

        if (t === "" || names.indexOf(t.toLowerCase()) !== -1) return { obj: app, ctx: "" };
        return { obj: t, ctx: app };
    }

    // 258 -> 420. 258 matched Media's widest back when it scrolled its
    // title; it is only the 34px wave now, and the workspace marks went
    // from ~200px of digits to ~130px of dots, so the room they freed
    // goes to the title, which elided far too early ("pas ... trop tôt").
    // At its widest the row is still well under the 840px Veille opens
    // the island to.
    readonly property int maxWidth: 420

    // objMeasure/ctxMeasure, not the visible labels, drive the width: the
    // labels are width-limited (and elided) by root's own width, so
    // reading them back into implicitWidth would close a binding loop.
    // These are free-standing, invisible, unconstrained Texts.
    // Placeholder text/width when there's no active window -- asked for:
    // leaving this at 0 while Media (mpris, the module symmetric to this
    // one across the fixed centerRow -- see shell.qml's ONE BAR) had
    // real content made the bar visibly lopsided, and vice versa. Not
    // meant to look "full", just enough to keep both sides roughly
    // balanced when only one of the two is actually active.
    readonly property string placeholderText: "Super + Space"

    // 8 (left) + 12 (right) around the text, + the 8 gap when there is a
    // context half.
    readonly property real ctxSpan: root.parts.ctx !== "" ? ctxMeasure.implicitWidth + 8 : 0
    implicitWidth: root.hasWindow
        ? Math.min(Math.max(objMeasure.implicitWidth + root.ctxSpan + 20, 92), maxWidth)
        : Math.max(placeholderMeasure.implicitWidth + 24, 92)   // 90 -> 92, point 6: 4pt grid
    // Animated width change, asked for -- title length changes (focus
    // switch, page/tab title update) now widen/narrow this module smoothly
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
        id: objMeasure
        text: root.parts.obj
        font.family: Fonts.ui
        font.pixelSize: 14
        font.weight: Font.Medium
        visible: false
    }
    Text {
        id: ctxMeasure
        text: root.parts.ctx
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
        color: Ink.muted   // colors.lua "muted" -- same token Hdr.qml uses for its own greyed-out state
        font.family: Fonts.ui
        font.pixelSize: 13
    }

    Row {
        visible: root.hasWindow
        anchors.left: parent.left
        anchors.leftMargin: 8
        anchors.verticalCenter: parent.verticalCenter
        spacing: 8

        // Where first, in grey, then what, in cream -- the order the bar
        // always had (app, then title); swapped for a day and swapped
        // back ("je me suis un peu habitué à l'avant").
        Text {
            renderType: Text.NativeRendering
            font.hintingPreference: Font.PreferNoHinting
            visible: root.parts.ctx !== ""
            text: root.parts.ctx
            color: DrawerTheme.islandMuted
            font.family: Fonts.ui
            font.pixelSize: 14
        }
        Text {
            renderType: Text.NativeRendering
            font.hintingPreference: Font.PreferNoHinting
            // Takes whatever the context half leaves; elides, so the app
            // or page before it stays readable however long the title runs.
            width: Math.max(0, Math.min(objMeasure.implicitWidth, root.width - 20 - root.ctxSpan))
            text: root.parts.obj
            color: DrawerTheme.cream
            font.family: Fonts.ui
            font.pixelSize: 14
            font.weight: Font.Medium
            elide: Text.ElideRight
        }
    }
}
