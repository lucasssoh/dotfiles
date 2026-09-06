import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import "modules" as Modules
import "modules/veille"
import "modules/balise"
import "services"
import "theme"

// ============================================================
// BAR — Quickshell port of waybar/config.jsonc + waybar/style.css.
//
// STATUS: ACTIVE (see install.sh, hypr/hyprland.lua). waybar/ is kept
// installed and in the repo as a fallback, not started -- quickshell/
// dashboard/ is the one still inactive, on purpose.
//
// v3: visual grouping matches waybar/style.css's actual color/border/
// radius rules (see modules/Block.qml) -- colors below are copied
// verbatim from its @define-color block, not colors.lua (the two have
// drifted apart over time; style.css is the source of truth for what
// the bar itself looks like).
//   background #0c0c0e  surface #1e1e20  overlay #34383f
//   overlay2   #505050  text    #f2f2f7  muted   #48484a
//   accent2    #4fefff  play    #237823  danger  #ff6e6e
//
// "Verre givré" pass (see hypr/hyprland.lua general.col.active_border):
// the neon accent2 #4fefff is replaced everywhere in this bar by #a8b4c4
// -- a blue desaturated almost to platinum/silver, the SAME token used
// in the Hyprland active-border gradient -- so the border around the
// focused window and the bar's own active-state color are literally one
// shared token now.
//
// No-border pass, right after: every block/chip/pill border (the glass
// rim this bar briefly had, and the accent "ghost ring" on the
// workspace pill / window chip) is gone. In its place, the two neutral
// tiers used for module fills were pushed further apart -- background
// #141414 -> #0c0c0e (deeper black), overlay #2c2c2e -> #34383f (a
// clearer graphite/platinum gray, same #a8b4c4 hue family, just darker
// and less saturated) -- so each block still reads as its own shape
// purely from fill contrast, no outline needed. text/muted/play/danger
// are unchanged.
//
// Merge passes, one after another, ending in a single bar: first the 2
// left pills (notif/clock/workspaces, window) collapsed into 1 and the 5
// right pills (cpu/temp/fan/mem, display/hdr, audio/bt/network, battery,
// perf/power) collapsed into 1; then those merged into ONE Block for the
// whole bar (see "── ONE BAR ──" below) -- not 3 zones anchored
// independently to the screen, one shape anchored by its OWN
// horizontalCenter to the screen's, so any content change anywhere in it
// shifts both edges outward symmetrically. 6px spacer Items mark what
// used to be separate pills, so former clusters still read as distinct
// groups without a border anywhere (audio/bt/network briefly had its own
// #34383f contrast tint here too, since removed -- see the METRICS/TOOLS
// pills below, where the notification bell and running-apps launchers
// ended up living instead of in this main bar). Media (mpris, far left)
// and ActiveWindow (far right,
// moved there from next to notif/clock/workspaces -- its context reads
// better toward the outside edge) are "les seuls vrais élargisseurs", the
// two modules whose width genuinely swings a lot, so it's mostly their
// growth that's visible -- but literally anything in the bar growing has
// the same two-sided effect. ActiveWindow and the workspace pill also
// animate their own width changes (Behavior on implicitWidth/width)
// instead of snapping; everything downstream of them follows for free
// through the normal width-binding chain, no extra Behavior needed
// anywhere else. Network's rate text is deliberately excluded from all of
// this (re-measures every 2s, see Network.qml) -- animating it would mean
// near-continuous relayout of the entire bar instead of an occasional
// smooth resize. No more custom position math anywhere either (the old
// mpris anti-collision x: calculation is gone entirely) -- a single Block
// lays out its own children left-to-right with no overlap by
// construction.
//
// mpris is the one deliberate departure from "match waybar exactly":
// GTK-CSS couldn't animate a width open/close in any interesting way,
// QML can, so it stretches open from the center when a player starts
// instead of just appearing (see modules/Media.qml).
//
// Per-module data mechanism (poll vs event-driven vs native) is
// unchanged from v2 -- see git history / prior conversation for that
// breakdown, this pass is purely visual.
// ============================================================

ShellRoot {
    id: shell

    // Zen/focus mode (was SUPER+Z -> `pkill -SIGUSR1 waybar`, waybar's
    // built-in "hide all bars" signal). No such signal exists for
    // quickshell, so it's just a shared bool flipped over IPC -- every
    // per-screen PanelWindow below binds its own `visible` to it, one
    // toggle hides/shows all of them at once. Unmapping the layer-shell
    // surface this way (not just an opacity/height animation) also frees
    // its exclusiveZone reservation, same as waybar hiding did -- tiled
    // windows actually reclaim the space instead of leaving a dead gap.
    property bool zenMode: false

    // Keybinds cheatsheet, shown while SUPER is HELD (see
    // hypr/keybinds.lua's "Super_L" bind, press/release calling
    // keybindsPress/keybindsRelease below) -- the second thing to ever
    // plug into DrawerIsland's slot, asked for explicitly as a test of
    // the "sans que ça ne soit forcement Veille" extensibility
    // centerIsland's own comment already called out. Shown on every
    // screen's bar at once (unlike Veille -- a hand-triggered cheatsheet
    // isn't the kind of "noise" repeating Veille on every monitor would
    // be).
    //
    // A genuine HOLD, not a press: SUPER is the modifier prefix for
    // nearly every other bind in keybinds.lua, so the key goes down
    // constantly in normal use (SUPER+E, SUPER+Space, ...) and showing
    // this on the bare press would flash it open on every one of them.
    // The first half of that filtering is Hyprland's own `long_press`
    // flag on the bind (see keybinds.lua) -- a quick tap emits nothing
    // here at all. This timer is the SECOND half, and the tunable one:
    // Hyprland's long-press threshold is fixed and fairly short, so
    // keybindsPress below only ARMS this, and the sheet appears once
    // SUPER has additionally been down this long.
    property bool keybindsVisible: false
    readonly property int keybindsHoldDelay: 350
    Timer {
        id: keybindsHoldTimer
        interval: shell.keybindsHoldDelay
        repeat: false
        onTriggered: shell.keybindsVisible = true
    }

    // Guard against the two binds arriving OUT OF ORDER. They're two
    // separate `qs ... ipc call` process spawns (~100ms each) racing
    // each other, so a release very shortly after the long-press
    // threshold can land BEFORE the press it's supposed to cancel --
    // which would leave the sheet opening onto an already-released key
    // and staying there. A press arriving within this window of the
    // last release is treated as that stale press and dropped.
    // Deliberately shorter than any real re-hold gesture, so holding
    // SUPER again right after letting go still works normally.
    property real keybindsLastReleaseMs: 0
    readonly property int keybindsReorderGuard: 250

    // The one place the sheet gets hidden, so the release bind and the
    // event fallback below can't drift apart. Stamping the release time
    // here too means a press still in flight behind either of them is
    // dropped by the reorder guard, whichever path got there first.
    function hideKeybinds(): void {
        keybindsHoldTimer.stop();
        shell.keybindsLastReleaseMs = Date.now();
        shell.keybindsVisible = false;
    }

    // Hyprland events that mean "a shortcut just DID something", used to
    // dismiss the sheet when its release bind never arrives.
    //
    // It doesn't arrive whenever the hold ended in an actual combo --
    // hold SUPER, press E, let go: nemo opens, but the sheet stays up.
    // That is Hyprland behaving as designed, not a bug to bind around: a
    // modifier's release bind is deliberately suppressed once another
    // key was pressed during the hold, which is exactly what stops
    // tap-to-launch bindings firing at the end of every SUPER+... combo.
    // The clean hold-and-release path still uses the release bind; this
    // covers the path where the compositor will never send one.
    //
    // A curated list rather than any raw event: `activewindow` in
    // particular fires on plain focus-follows-mouse, which would snap
    // the sheet shut just for moving the mouse while reading it. These
    // are all consequences of a deliberate action instead.
    readonly property var keybindsDismissEvents: [
        "openwindow", "closewindow", "workspace", "workspacev2",
        "movewindow", "movewindowv2", "fullscreen", "changefloatingmode",
        "submap", "focusedmon"
    ]

    // Alias, not the bare `veille` id, for anything reading this from
    // INSIDE the Variants delegate below -- confirmed live that a plain
    // sibling id declared elsewhere in this file (however positioned in
    // reading order) resolves to null from within a Variants-instantiated
    // PanelWindow ("TypeError: Cannot read property 'suppressed' of
    // null"), while `shell`'s own id does not. `shell.veille` is then
    // just an ordinary property read on an object already known to
    // resolve, sidestepping whatever that scoping boundary actually is.
    property alias veille: veilleInstance

    // One bar per currently-connected screen, automatically -- Quickshell
    // creates/destroys instances as monitors plug/unplug, no manual
    // single/dual-output branching needed. Workspaces and HDR are
    // per-monitor correct too: Hyprland.monitorFor(bar.screen) bridges
    // Quickshell's screen object to the matching HyprlandMonitor, passed
    // down so each bar reads its OWN screen instead of whichever monitor
    // happens to be globally focused (see modules/Workspaces.qml,
    // modules/Hdr.qml, and modules/ActiveWindow.qml's `monitor`
    // property). ActiveWindow still shows Hyprland.activeToplevel's
    // TITLE (Hyprland doesn't expose a separate "last active window on
    // monitor X" the way it does monitorFor()), but whether to show
    // anything at all is now gated on THIS monitor's own activeWorkspace
    // having a real (non-floating) toplevel -- see its own header
    // comment for why the naive global-focus check wasn't enough.

    // External nudge for the "hl.dispatch-routed actions don't emit
    // Hyprland IPC events" problem (see Hdr.qml's header comment) --
    // scripts/compact-workspaces.sh (SUPER+C) moves windows between
    // workspaces via hl.dsp.window.move(), which left this bar showing
    // stale workspace occupancy until something else happened to
    // refresh it. One handler, not per-screen: Hyprland.refresh*() are
    // global singleton calls, calling them once updates every bar
    // instance's view at once. `qs -c bar ipc call bar
    // refreshWorkspaces` from any external script reaches this.
    IpcHandler {
        target: "bar"
        function refreshWorkspaces(): void {
            Hyprland.refreshWorkspaces();
            Hyprland.refreshToplevels();
        }
        function toggleZen(): void {
            shell.zenMode = !shell.zenMode;
        }
        // Brightness has no DBus/kernel push to react to (see
        // services/OsdState.qml's header) -- keybinds.lua calls this
        // right after brightnessctl so the OSD shows the freshly-set
        // level. `quickshell ipc call -c bar bar pokeBrightness`.
        function pokeBrightness(): void {
            OsdState.pokeBrightness();
        }
        // Preview the low-battery alert on demand -- there's no real
        // battery to trigger it on a desktop. Bypasses the actual
        // UPower state/tier tracking entirely (see
        // BatteryAlertState.qml's simulate). `qs -c bar ipc call bar
        // simulateBattery 8`.
        function simulateBattery(percent: int): void {
            BatteryAlertState.simulate(percent);
        }
        // Dismiss it again without clicking Close by hand -- the alert
        // has no auto-hide timer (asked for, matches the reference), so
        // a simulateBattery test run needs an explicit way back down.
        function dismissBattery(): void {
            BatteryAlertState.dismiss();
        }
        // Preview Battery.qml's own top-bar module -- separate from
        // simulateBattery above, which only drives the low-battery
        // ALERT. No real UPower/power-profiles-daemon state touched
        // (see BatteryPreviewState.qml). `qs -c bar ipc call bar
        // previewBattery 62 false` (percent, charging).
        function previewBattery(percent: int, charging: bool): void {
            BatteryPreviewState.set(percent, charging);
        }
        function previewBatteryOff(): void {
            BatteryPreviewState.clear();
        }
        // `qs -c bar ipc call bar keybindsPress`/`keybindsRelease` --
        // hypr/keybinds.lua's Super_L bind calls these on key down/up.
        // Press only ARMS the hold timer above (it does NOT show
        // anything on its own); release both disarms it and hides, so
        // whichever of the two the gesture ends on, the state is
        // consistent. `restart()` rather than `start()` so a repeat
        // key-down (autorepeat, or a press whose release got lost)
        // re-arms from zero instead of being ignored as "already
        // running".
        function keybindsPress(): void {
            if (Date.now() - shell.keybindsLastReleaseMs < shell.keybindsReorderGuard)
                return;
            keybindsHoldTimer.restart();
        }
        function keybindsRelease(): void {
            shell.hideKeybinds();
        }
        // Called by the companion bind keybinds.lua attaches to every
        // SUPER+... combo (see its `bind` wrapper): the combo means the
        // hold has turned into a real shortcut, and Hyprland will not
        // send a release bind for it. Separate name from
        // keybindsRelease even though both hide today -- one means "the
        // key came up", the other "something else happened".
        function keybindsHide(): void {
            shell.hideKeybinds();
        }
        // Replaces `swaync-client -t -sw` -- hypr/keybinds.lua's SUPER+I
        // calls this now, same IPC shape as toggleZen above. No
        // per-screen click context on this path (unlike the bell click
        // itself, which passes its own bar.screen) -- defaults to the
        // first screen, acceptable for a keybind with no click position
        // to derive one from.
        function toggleNotificationCenter(): void {
            NotificationState.toggleNotificationCenter(Quickshell.screens[0]);
        }
        // Close-only (not a toggle) -- waybar/scripts/balise-toggle.sh
        // calls this right before showing Balise, same mutual-exclusion
        // swaync-client -cp used to give it.
        function closeNotificationCenter(): void {
            NotificationState.close();
        }
    }

    // Same belt-and-suspenders safety net as Hdr.qml's own onRawEvent
    // refresh (see its header comment), applied here for the same reason:
    // workspace-manager.sh and compact-workspaces.sh both nudge
    // refreshWorkspaces explicitly now, covering the two KNOWN sources of
    // "pill shows stale occupancy/highlight" (hl.* actions dispatched via
    // `hyprctl eval`, which don't emit IPC events -- see those scripts).
    // This catches whatever's left over: any other script/wheel action
    // using the same eval path that forgets the nudge, or plain event
    // ordering hiccups. `Hyprland.refreshWorkspaces()`/`refreshToplevels()`
    // just re-sync over the already-open IPC socket (no exec, no poll of
    // an external process) -- cheap enough to run on every raw event.
    Connections {
        target: Hyprland
        function onRawEvent(event) {
            Hyprland.refreshWorkspaces();
            Hyprland.refreshToplevels();

            // Fallback dismissal for the keybinds sheet -- see
            // keybindsDismissEvents' own comment for why the release
            // bind can't be relied on alone. Cheap: a string compare
            // against a 10-entry list, and only while the sheet is
            // actually up.
            if (shell.keybindsVisible
                && shell.keybindsDismissEvents.indexOf(event.name) !== -1) {
                shell.hideKeybinds();
            }

            // Same trick closes the notification drawer now that it
            // lives inside this always-present window (a DrawerIsland
            // entry, see toolsIsland above) instead of its own separate
            // focusable PanelWindow -- HyprlandFocusGrab's outside-click
            // detection doesn't apply here any more, but the underlying
            // problem it solved (layer-shell surfaces never get a real
            // focus-loss event) is the exact same one Balise's own
            // scripts/balise-autoclose.sh works around externally via
            // Hyprland's `activewindow` event. Reusing
            // keybindsDismissEvents rather than bare `activewindow`
            // directly, and for the same documented reason above it: raw
            // `activewindow` also fires on plain focus-follows-mouse,
            // which would close the drawer just from moving the pointer
            // over another window while reading a notification.
            if (NotificationState.centerOpen
                && shell.keybindsDismissEvents.indexOf(event.name) !== -1) {
                NotificationState.close();
            }

            // Same close mechanism for Balise's own drawer -- see
            // BaliseState.qml's header for why the two are mutually
            // exclusive rather than stacking, this is the other half:
            // closing on outside interaction, not just when the other
            // one opens.
            if (BaliseState.panelOpen
                && shell.keybindsDismissEvents.indexOf(event.name) !== -1) {
                BaliseState.close();
            }
        }
    }

    // Sleep-awareness clock -- LOGIC only now (see modules/veille/
    // Veille.qml's own header for why the rendering moved into each
    // bar's own central island instead of a separate overlay window).
    // Still single instance, not inside the Variants below: unlike the
    // bar itself, this isn't per-screen content -- every bar below reads
    // this same instance (via `shell.veille`, see that alias's own
    // comment) and only actually opens ITS drawer when `bar.screen ===
    // shell.veille.activeScreen`. zenMode threaded in exactly the way
    // ActiveWindow.qml's `monitor` property is (a plain pass-through, no
    // singleton needed for one consumer). `id: veilleInstance`, not
    // `veille` -- `shell`'s own `veille` alias (above) points at this;
    // see its comment for why the Variants delegate below reads it
    // through that instead of this id directly.
    Veille {
        id: veilleInstance
        zenMode: shell.zenMode
    }

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: bar
            required property var modelData
            screen: modelData

            focusable: false
            visible: !shell.zenMode
            // exclusiveZone stays at the main bar's own height (24), not
            // the window's full implicitHeight below (30) -- the metrics
            // pill's extra 6px is purely decorative floating space, not
            // reserved from tiled windows (same reasoning the corner-flare
            // experiment used, before it got reverted for a different
            // reason: the pixel math itself was fine).
            exclusiveZone: 24
            aboveWindows: true
            color: "transparent"

            anchors { top: true; left: true; right: true }
            // Content is now a single centered island (see "── ONE BAR ──"
            // below), not 3 zones spanning the full width, so left/right
            // margins rarely matter in practice any more --
            // kept at 0 anyway (harmless, and still correct if content
            // ever does grow wide enough to reach an actual screen edge).
            // top: 0 still matters always -- the main bar stays flush
            // against the screen's top edge regardless of horizontal
            // content (its Block's top corners are unconditionally square,
            // see Block.qml's flushTop -- squareLeft/squareRight there are
            // unused now but kept for the same "still correct if it ever
            // reaches an edge" reason).
            margins { top: 0; left: 0; right: 0 }
            // centerIsland's own maxHeight (a DrawerIsland -- see that
            // component's own comment), NOT its current/animated
            // `height` -- the real Wayland surface is allocated ONCE at
            // the tallest it could ever need to be and never actually
            // resized at the compositor level while the drawer opens/
            // closes, only the in-scene content within it does (a real
            // per-frame surface resize was a plausible source of visible
            // hitches right at the start/end of that transition). Always
            // >= rowHeight (31) even with no drawer content at all --
            // still implicitly >= metrics' own bottom extent too (3 top
            // gap + its content, ~27, less than rowHeight). The main
            // bar's Row stays flush at y:0 regardless (anchors.top);
            // metrics/the drawers use the extra space below, which just
            // renders as empty/transparent (and stays outside the input
            // mask below) whenever a drawer isn't fully open.
            //
            // Math.max, not just centerIsland's own -- toolsIsland now
            // grows a drawer too (NotificationCenter), and its own
            // maxHeight (rowHeight + a 600px-tall entry) is taller than
            // centerIsland's ever gets. Sizing off centerIsland alone
            // would clip the notification drawer at whatever height
            // centerIsland happened to need instead of the drawer's own
            // real full-open height.
            implicitHeight: Math.max(centerIsland.maxHeight, toolsIsland.maxHeight)

            // Input stays restricted to the NORMAL bar's own height
            // (centerIsland.rowHeight, 31) regardless of how tall the
            // surface's implicitHeight above grows once its drawer
            // opens -- asked for on the standalone overlay Veille's own
            // drawer replaced ("ne bloque jamais les clics") and just as
            // true here: the drawer can now visually extend well past
            // the 24px exclusiveZone into space real windows occupy, and
            // without this it would swallow clicks meant for whatever's
            // underneath. Every existing clickable module (Workspaces,
            // Media, metrics...) sits within this same top rowHeight
            // already, so this changes nothing for them.
            //
            // TWO regions now, not one blanket full-width strip: TOOLS'
            // own drawer (NotificationCenter) can extend well past that
            // same rowHeight when open, and its actual content (buttons,
            // the notification list) needs to stay clickable -- a single
            // bar-width mask fixed at rowHeight would swallow clicks into
            // it exactly the way this comment says the mask exists to
            // PREVENT elsewhere. `Region`'s own default `regions` list
            // property unions any nested Regions (confirmed against
            // Quickshell's own Region type), so this is a real two-rect
            // mask, not one region silently overriding the other: the
            // first covers the always-present top strip end to end
            // (unchanged), the second covers just TOOLS' own x-range, at
            // ITS live height (toolsIsland.height already tracks its
            // drawer's own open/close animation, no separate state to
            // keep in sync).
            mask: Region {
                Region {
                    x: 0
                    y: 0
                    width: bar.width
                    height: centerIsland.rowHeight
                }
                Region {
                    x: toolsIsland.x
                    y: 0
                    width: toolsIsland.width
                    height: toolsIsland.height
                }
            }

            // ── ONE BAR ───────────────────────────────────────
            // ActiveWindow, Workspaces and Media, in ONE Row, centered
            // on the screen as a whole -- see DrawerIsland.qml for the
            // actual pill/drawer mechanics (background, corner radii,
            // GlassRim, the gloss highlight, the drawer-below-the-row
            // layout). Factored out into that reusable component,
            // rather than written inline here a second time, specifically
            // so shell.qml and preview.qml (the review tool) share ONE
            // implementation instead of two independently-coded copies
            // that can drift apart -- asked for explicitly ("eviter de
            // coder deux fois à la fois veille et preview"). Went
            // through two rejected in-between designs first (see
            // DrawerIsland.qml's own header for that history) before
            // landing on "one Row, centered as a whole" -- Workspaces
            // CAN shift now when ActiveWindow/Media resize, accepted as
            // the tradeoff for the whole shape staying an exact snug fit
            // around whatever's actually in it, not padded to match
            // whichever side is currently wider.
            //
            // Clock used to sit here too -- moved into the tools pill
            // (right before the power dot) and given a date alongside it,
            // asked for.
            Modules.DrawerIsland {
                id: centerIsland
                anchors.top: parent.top
                anchors.horizontalCenter: parent.horizontalCenter

                // `shell.veille` is the single shared logic instance
                // (see Veille.qml's own header, and `shell`'s own
                // `veille` alias comment for why it's read through that
                // rather than a bare id) -- every screen's bar reads it,
                // but only the one matching `activeScreen` ever actually
                // opens ITS drawer; every other screen's `drawerOpen`
                // here just stays permanently false. `drawerItem` is any
                // Item -- "ça permettra de centraliser aussi plus tard
                // [un] widget qui se déclenche dans cet endroit sans que
                // ça ne soit forcement Veille" -- Veille was the first
                // thing plugged in here; the keybinds cheatsheet is the
                // second, proving that comment out.
                //
                // They STACK rather than compete: each entry carries its
                // own `drawerOpen`, and the island extends once further
                // for each one that opens. So holding SUPER while
                // Veille's clock is already showing adds the cheatsheet
                // underneath it instead of replacing it, and letting go
                // retracts by exactly that much again. Listed here in
                // the order they stack, top to bottom. `drawerItems`,
                // not bare children -- an unnamed child of a
                // DrawerIsland lands in its TOP row instead, via its
                // default-property alias.
                drawerItems: [
                    VeilleDrawerContent {
                        veille: shell.veille
                        drawerOpen: !shell.veille.suppressed && bar.screen === shell.veille.activeScreen
                    },
                    Modules.KeybindsDrawerContent {
                        drawerOpen: shell.keybindsVisible
                    }
                ]

                // opacity 0.9 matches waybar/style.css's old #window
                // rule (the whole element, not just its text).
                Modules.ActiveWindow {
                    opacity: 0.9
                    monitor: Hyprland.monitorFor(bar.screen)
                }
                Modules.Workspaces { monitor: Hyprland.monitorFor(bar.screen) }
                // Media (mpris) -- no Launchers inside any more (asked
                // for, a while back: pulled out into its own separate
                // floating island, see below).
                Modules.Media {}
            }

            // ── METRICS (separate from the main bar, top-left) ─
            // Pulled out entirely, asked for -- "le moins élégant, mais
            // j'en ai besoin": cpu/temp/fan/mem/battery, the actual numeric
            // hardware readouts. Split from "tools" below (display/hdr/
            // connectivity -- status indicators, not really "metrics") and
            // put on the opposite side, asked for. Floats on its own
            // instead, the way mpris used to float independently before
            // any of this session's changes: NOT flush against the top
            // edge (3px gap -- was 6, halved to sit closer to the main
            // bar's own top, asked for; flushTop: false so its top corners
            // are rounded like every other side -- see Block.qml), NOT
            // flush against the left edge either (6px gap), and an
            // almost-transparent fill (#0c0c0e at ~45% alpha) instead of
            // the main bar's solid one, so it reads as a lightweight
            // overlay, not another equally-weighted bar.
            Modules.Block {
                id: metrics
                anchors.top: parent.top
                anchors.topMargin: 3
                anchors.left: parent.left
                anchors.leftMargin: 6
                flushTop: false
                color: "#730c0c0e"
                // Glass. These three float free of every screen edge, so
                // all four of their edges are visible -- the one place in
                // this bar where a pane read is possible at all.
                //
                // Two separate light sources, on purpose. The FILL is a
                // vertical gradient (denser and lighter at the top,
                // thinner and darker at the bottom) -- that's the body of
                // the pane. The EDGE is a GlassRim sibling below, tracing
                // the same five-stop diagonal Hyprland/Roue/Balise use --
                // that's the highlight raking across it. A flat
                // border.color was tried for the edge first and read as
                // exactly what it was: a uniform light outline.
                //
                // Vertical, not the 135deg used in balise/style.css: these
                // are ~24px tall and several hundred wide, so a diagonal
                // would be swallowed by the width and read as a horizontal
                // wash. Top-to-bottom is the only axis with enough travel.
                //
                // Deliberately NOT applied to the central island: it's
                // flush against the screen's top edge and ~43:1, so only
                // its bottom edge is ever visible -- a rim there was tried
                // and dropped, it read as a stray underline rather than as
                // a pane. Block.qml's no-border rule still holds for the
                // solid blocks; these translucent ones are the exception.
                // Both stops keep the SAME 0x73 alpha the flat fill had.
                // Varying alpha instead (tried first) lets a different
                // amount of wallpaper through at each end, which fights the
                // gradient rather than adding to it -- measured: only 16
                // units of travel, 10 of which were already there from the
                // wallpaper alone. Constant alpha means the travel comes
                // purely from the colour and is the same over any
                // wallpaper.
                gradient: Gradient {
                    GradientStop { position: 0.0; color: "#733f4450" }
                    GradientStop { position: 1.0; color: "#73060608" }
                }

                Item { width: 6; height: 1 }

                Modules.Cpu {}
                Modules.Temperature {}
                Modules.Fan {}
                Modules.Memory {}
                // Moved here from Network.qml in TOOLS (asked for) --
                // the download-rate half of what used to be one combined
                // wifi/rate module, now grouped with METRICS' other
                // continuously-updating stats instead.
                Modules.Traffic {}
            }

            // Launchers -- its own separate floating island (asked for:
            // out of the central island entirely, and placed in front of
            // TOOLS rather than trailing the island). Right edge anchored
            // to TOOLS' own left edge (`toolsIsland`, now a DrawerIsland
            // rather than a plain Block) instead of chasing the island's
            // dynamic width -- sits at a stable position relative to the
            // screen's right edge, same as METRICS/TOOLS themselves,
            // rather than sliding around whenever ActiveWindow/Media/
            // workspaces resize.
            Modules.Block {
                id: launchers
                anchors.top: parent.top
                anchors.topMargin: 3
                anchors.right: toolsIsland.left
                anchors.rightMargin: 6
                flushTop: false
                color: "#730c0c0e"
                // Glass. These three float free of every screen edge, so
                // all four of their edges are visible -- the one place in
                // this bar where a pane read is possible at all.
                //
                // Two separate light sources, on purpose. The FILL is a
                // vertical gradient (denser and lighter at the top,
                // thinner and darker at the bottom) -- that's the body of
                // the pane. The EDGE is a GlassRim sibling below, tracing
                // the same five-stop diagonal Hyprland/Roue/Balise use --
                // that's the highlight raking across it. A flat
                // border.color was tried for the edge first and read as
                // exactly what it was: a uniform light outline.
                //
                // Vertical, not the 135deg used in balise/style.css: these
                // are ~24px tall and several hundred wide, so a diagonal
                // would be swallowed by the width and read as a horizontal
                // wash. Top-to-bottom is the only axis with enough travel.
                //
                // Deliberately NOT applied to the central island: it's
                // flush against the screen's top edge and ~43:1, so only
                // its bottom edge is ever visible -- a rim there was tried
                // and dropped, it read as a stray underline rather than as
                // a pane. Block.qml's no-border rule still holds for the
                // solid blocks; these translucent ones are the exception.
                // Both stops keep the SAME 0x73 alpha the flat fill had.
                // Varying alpha instead (tried first) lets a different
                // amount of wallpaper through at each end, which fights the
                // gradient rather than adding to it -- measured: only 16
                // units of travel, 10 of which were already there from the
                // wallpaper alone. Constant alpha means the travel comes
                // purely from the colour and is the same over any
                // wallpaper.
                gradient: Gradient {
                    GradientStop { position: 0.0; color: "#733f4450" }
                    GradientStop { position: 1.0; color: "#73060608" }
                }

                Modules.Launchers {
                    opacity: 0.8
                }
            }

            // ── TOOLS (separate from the main bar, top-right) ──
            // display/hdr/connectivity/perf/power -- status/toggle
            // indicators, split from METRICS. Same floating treatment
            // (3px top gap, 6px right gap, rounded corners, translucent
            // fill) -- now a DrawerIsland (was a plain Block) so it can
            // host the notification center as a real drawer, same
            // mechanism centerIsland already uses for Veille/Keybindings
            // (asked for explicitly, after a first pass built the
            // notification center as its own separate floating
            // PanelWindow+HyprlandFocusGrab instead). `flushTop: false` +
            // the fillGradient below reproduce this pill's original
            // floating/translucent look (see DrawerIsland.qml's own
            // header for why that needed generalizing -- it was
            // hardcoded for centerIsland's flush-top/opaque-black look
            // until now). `rowSpacing: 0` keeps this row's existing
            // hand-tuned Item spacers (the "6 -> 3 -> 2" gaps below)
            // working as before -- centerIsland's own top row has no
            // manual spacers and relies on DrawerIsland's 6px default
            // instead, so that default had to become overridable rather
            // than just lowering it outright.
            Modules.DrawerIsland {
                id: toolsIsland
                anchors.top: parent.top
                anchors.topMargin: 3
                anchors.right: parent.right
                anchors.rightMargin: 6
                flushTop: false
                // ONE gap for the whole row -- asked for: "regularise le
                // gap entre chaque bloc de module dans tools island". This
                // was `rowSpacing: 0` plus a hand-tuned `Item` spacer
                // between each pair, which had drifted to 0 / 6 / 6 / 2 /
                // 2 / 2 / 2 across the row (three separate tuning passes,
                // each touching only the cluster it was about). Now the
                // spacing is structural and cannot drift again: one number
                // here, and the only Items left in the row are the two
                // matching end paddings.
                //
                // 2, down from the 4 this landed on when the gaps were
                // first regularized -- the "compact" half of the same
                // request that unpinned the width below. Not a fresh
                // guess: 2 is where the right-hand cluster had already
                // been tuned by hand over three passes ("6 -> 3 -> 2",
                // "ça consomme trop d'espace"), so it is the one tight
                // value already validated on this row. It now applies to
                // the whole row instead of a third of it.
                rowSpacing: 2
                twoPhase: false
                // Snappier stretch+fade than DrawerIsland's defaults --
                // asked for ("l'animation de elargissement fade se fasse
                // un peu plus rapidement"), and set HERE, on this island
                // alone, rather than by lowering the component's own
                // defaults. centerIsland must keep the feel it has: "il
                // ne faut pas affecter les animations et effet de
                // l'island du milieu". It overrides none of these, so it
                // still runs 320/200/140/260/260/220 exactly as before.
                //
                // revealDuration has to stay equal to the `Behavior on
                // height` of THIS island's entries -- NotificationCenter
                // .qml and BaliseHome.qml, both 220 to match. Anything
                // else and the content fade starts mid-stretch.
                revealDuration: 220
                contentFadeDuration: 150
                contentFadeOutDuration: 110
                panelFadeDuration: 200
                // twoPhase is false here, so this one only feeds the
                // plain `Behavior on openProgress` (the row's own rare
                // width shifts, e.g. BaliseButton's IconSlot); the
                // narrow leg it would pair with is openSequence's, which
                // never runs in this mode.
                widenDuration: 180
                // Matches METRICS' own Block height exactly (asked for:
                // closed, this pill was sitting 7px lower than METRICS --
                // DrawerIsland's 31px default was tuned for centerIsland's
                // row, not this one).
                rowHeight: 24
                fillColor: "#730c0c0e"
                // UNPINNED -- the pill tracks its own content again,
                // asked for: "j'aimerai que ce soit compact et que ça
                // s'adapte avec le nombre d'element à l'interieur".
                //
                // This deliberately reverses the earlier `fixedContentWidth:
                // 416` (asked for then as "fixer la largeur pour match la
                // largeur du modules tools. il ne doit absolument pas
                // bouger"). That number was measured with every module
                // showing, so whenever one is not -- the battery is hidden
                // on this machine unless discharging, which is most of the
                // time -- the row sat 52px narrower than the shape drawn
                // around it, and that dead air IS the thing that reads as
                // not compact.
                //
                // What the pin was protecting against is mostly gone
                // anyway: the two modules whose text changes width
                // (Battery, and the audio readouts until this same pass
                // removed them) both size their digits against a hidden
                // "100" slot, so a percentage going 100 -> 9 no longer
                // moves anything. What is left is modules appearing or
                // disappearing outright (battery, the HDR chip), which is
                // occasional rather than continuous -- and this island is
                // anchored by its RIGHT edge, so those only ever move the
                // left one.
                //
                // ...and the drawer follows that width, rather than
                // setting one of its own: "la largeur du tiroir doit
                // suivre impérativement celle de la barre (pour les
                // tiroirs à droite)". So the pill measures itself against
                // its own icons, and the notification center and Balise
                // open at exactly that width -- both of them size every
                // section off `parent.width` rather than a literal number,
                // which is what makes that work (see
                // NotificationCenter.qml's header).
                fixedContentWidth: 0
                // ...and opening must not widen the pill either -- see
                // DrawerIsland's own comment for why the default would
                // have added the hidden Battery module's width here.
                widenOnOpen: false
                // Translucent panel, opaque cards on top of it -- see
                // theme/Surfaces.qml for the whole rule. Only TOOLS gets
                // it: centerIsland's drawers draw bare text with no card
                // behind it.
                drawerFillTop: Surfaces.panelTop
                drawerFillBottom: Surfaces.panelBottom

                drawerItems: [
                    Modules.NotificationCenter {
                        drawerOpen: NotificationState.centerOpen && NotificationState.activeScreen === bar.screen
                    },
                    BaliseHome {
                        drawerOpen: BaliseState.panelOpen && BaliseState.activeScreen === bar.screen
                    }
                ]
                // Glass. These three float free of every screen edge, so
                // all four of their edges are visible -- the one place in
                // this bar where a pane read is possible at all.
                //
                // Two separate light sources, on purpose. The FILL is a
                // vertical gradient (denser and lighter at the top,
                // thinner and darker at the bottom) -- that's the body of
                // the pane. The EDGE is a GlassRim sibling below, tracing
                // the same five-stop diagonal Hyprland/Roue/Balise use --
                // that's the highlight raking across it. A flat
                // border.color was tried for the edge first and read as
                // exactly what it was: a uniform light outline.
                //
                // Vertical, not the 135deg used in balise/style.css: these
                // are ~24px tall and several hundred wide, so a diagonal
                // would be swallowed by the width and read as a horizontal
                // wash. Top-to-bottom is the only axis with enough travel.
                //
                // Deliberately NOT applied to the central island: it's
                // flush against the screen's top edge and ~43:1, so only
                // its bottom edge is ever visible -- a rim there was tried
                // and dropped, it read as a stray underline rather than as
                // a pane. Block.qml's no-border rule still holds for the
                // solid blocks; these translucent ones are the exception.
                // Both stops keep the SAME 0x73 alpha the flat fill had.
                // Varying alpha instead (tried first) lets a different
                // amount of wallpaper through at each end, which fights the
                // gradient rather than adding to it -- measured: only 16
                // units of travel, 10 of which were already there from the
                // wallpaper alone. Constant alpha means the travel comes
                // purely from the colour and is the same over any
                // wallpaper.
                fillGradient: Gradient {
                    GradientStop { position: 0.0; color: "#733f4450" }
                    GradientStop { position: 1.0; color: "#73060608" }
                }

                    // Left/right breathing room -- asked for, left
                    // especially (Block.qml's own Row has zero built-in
                    // padding, content starts flush at x:0, and
                    // ScriptModule's own centering math wasn't enough to
                    // clear the pill's rounded left edge on its own).
                    // Equal on both ends now, and the ONLY two spacer
                    // Items left in this row -- everything between two
                    // modules is `rowSpacing` above.
                    Item { width: 4; height: 1 }

                    // Hdr before the display-layout status now (asked
                    // for) -- was the other way around.
                    Modules.Hdr { monitor: Hyprland.monitorFor(bar.screen) }

                    Modules.ScriptModule {
                        command: ["bash", "-c", "$HOME/.config/hypr/scripts/display-layout.sh status"]
                        interval: 5000
                        // minWidth was the real culprit: implicitWidth is
                        // Math.max(label.implicitWidth + padding, minWidth) --
                        // with a short status text/icon, minWidth (50) was
                        // winning over content+padding, and centering a small
                        // label in that wider box is exactly what read as a
                        // gap on the left. Dropped low enough that padding
                        // actually governs the width for realistic content.
                        minWidth: 30
                        padding: 6
                        clickCommand: ["bash", "-c",
                            "$HOME/.config/hypr/scripts/display-layout.sh roue-gen && $HOME/.local/bin/roue display"]
                        classColors: ({
                            "display-both": "#f2f2f7",
                            "display-internal": "#a8b4c4",
                            "display-external": "#a8b4c4"
                        })
                    }

                    // Network's rate text re-measures its digit count every
                    // 2s (see Network.qml's Timer) -- deliberately NOT
                    // width-animated, so a rate-text change still just
                    // snaps this pill's width instantly instead of
                    // triggering a smooth (but then near-continuous)
                    // resize. No more #34383f contrast background behind
                    // these -- asked for, sits directly on the pill's own
                    // translucent fill now, same as everything else in it.
                    //
                    // Bluetooth/Network/Ethernet's three separate icons
                    // replaced by BaliseButton -- one consolidated bordered
                    // block (own badge+GlassRim, like Hdr) that opens
                    // Balise directly, asked for alongside Balise itself
                    // dropping its tab-header concept. The three old
                    // modules are left in the repo, just unreferenced here.
                    // These three used to sit in a nested `Row` of their
                    // own, which grouped them visually by gluing them at
                    // spacing 0 while everything around them had a gap.
                    // Dissolved into this row: they are three separate
                    // module blocks like any other, so they take the same
                    // regular gap. The Row carried no shared property, it
                    // was only ever the grouping.
                    Modules.AudioOutput {}
                    Modules.AudioInput {}
                    Modules.BaliseButton { screen: bar.screen }

                    // Performance profile + power, moved here from the main
                    // bar (were next to notif/clock/workspaces), asked for:
                    // now sit right of connectivity in this pill instead.
                    Modules.Performance {}

                    // Moved here from METRICS (asked for): sits between
                    // power-profile and the clock now, grouped with the
                    // other power/status modules instead of CPU/RAM/fan.
                    Modules.Battery {}

                    // Clock (+ date) -- moved out of dead-center (see
                    // barRow's own comment above) to right before the
                    // power dot, asked for.
                    Modules.Clock {}

                    // Notification bell -- moved again (asked for:
                    // "entre clock et power", i.e. the literal power dot
                    // below, not the power-PROFILE icon it sat next to
                    // before) -- was leftmost, then next to Hdr, then
                    // between Battery and Clock, before landing here.
                    Modules.NotificationBell { screen: bar.screen }

                    Item {
                        // 28 -> 20 -> 16: same space-saving pass as the
                        // other spacers in this cluster -- this box's own
                        // width is the gap before the power dot (the
                        // notification bell now sits between it and Clock,
                        // asked for). Still bigger than the 8px dot
                        // itself, just a tighter click target than
                        // before rather than a roomy one.
                        implicitWidth: 16
                        implicitHeight: 24

                        // Plain filled dot instead of a glyph (was 󰍃, before
                        // that ⏻) -- asked for: "un point dense, un petit
                        // disque plein". A real Rectangle/radius circle
                        // renders as a crisp, consistently dense disc at any
                        // size, where a font glyph's weight/shape varies
                        // with hinting. Same red as before.
                        Rectangle {
                            anchors.centerIn: parent
                            width: 8
                            height: 8
                            radius: width / 2
                            color: "#ff6e6e"
                        }

                        MouseArea {
                            anchors.fill: parent
                            onClicked: Quickshell.execDetached(["bash", "-c", "$HOME/.local/bin/roue power"])
                        }
                    }

                    // Matches the leading spacer -- see its comment.
                    Item { width: 4; height: 1 }
                }

            // Gradient edges for the two remaining translucent Blocks.
            // Siblings, not children: Block reparents anything nested
            // inside it into its content Row (see modules/GlassRim.qml).
            // Declared after both so they paint on top of their fills.
            // TOOLS used to get the same treatment here too, until it
            // became a DrawerIsland -- that component now draws its own
            // equivalent pair internally (see DrawerIsland.qml's
            // `flushTop: false` branch), so an external declaration here
            // would just double it up.
            //
            // Two per pill now (asked for): the main topLeft source at
            // full strength, plus a second, fainter one from bottomRight
            // -- light catching the far corner too, not just one flat
            // source. Weaker (0.45, not 1.0) so it reads as fill light,
            // not a second equally-strong highlight competing with the
            // real one.
            Modules.GlassRim { target: metrics }
            Modules.GlassRim { target: metrics; lightOrigin: "bottomRight"; strength: 0.45 }
            Modules.GlassRim { target: launchers }
            Modules.GlassRim { target: launchers; lightOrigin: "bottomRight"; strength: 0.45 }
        }
    }

    // Volume/mic/brightness OSD -- see services/OsdState.qml for the
    // trigger logic (Pipewire push for volume/mic, IPC-poked sysfs read
    // for brightness). Per-screen like the bar itself (not single-
    // instance like Veille above): there's no one obvious "the" screen
    // to pop it on without a focused-monitor lookup this codebase
    // doesn't have wired up yet, and showing it on every connected
    // screen is the harmless default while there's usually just one
    // anyway. Window stays mapped at all times (unlike the main bar's
    // `visible: !shell.zenMode` hard unmap) so Osd.qml's own opacity/
    // scale Behavior can actually fade it, not just pop.
    //
    // exclusionMode: Ignore is load-bearing, not decorative -- leaving
    // exclusiveZone unset was WRONG (found live, tiled windows visibly
    // shifted up/lost the bottom 48+60px strip): PanelWindow's default
    // exclusionMode is Auto, which computes an exclusive zone from the
    // anchored edge + size on its own, same as if exclusiveZone had been
    // set explicitly. Ignore is the only way to get a genuinely
    // non-reserving overlay, matching what this popup is actually
    // supposed to be -- floating over tiled windows, never pushing them.
    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: osdWindow
            required property var modelData
            screen: modelData

            focusable: false
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            // Missed on the first pass -- only the main bar had this.
            // Found live: a maximized/fullscreen window covered the OSD
            // entirely, since without it the popup wasn't necessarily on
            // top of regular application windows.
            aboveWindows: true

            anchors { bottom: true }
            margins.bottom: 48
            implicitWidth: osd.width
            implicitHeight: osd.height

            // Input region, not paint state -- the same fix
            // batteryAlertWindow above already carries, missed here on
            // that pass and reported live for the volume/brightness
            // popup ("même soucis d'invisibilité superficielle sur les
            // retour scroll de luminosité et de volume en bas au
            // milieu"). Osd.qml hides with `opacity: 0`, which leaves
            // the card at its full 280x92, and `implicitWidth/Height`
            // above read that size whether or not anything is showing --
            // so an unmasked layer surface was taking input across a
            // permanent invisible rectangle at bottom-center, 48px up.
            //
            // ALWAYS empty here, where the battery alert's own mask is
            // merely empty-while-hidden: that card is click-to-dismiss
            // and so needs input while it shows, but the OSD is a pure
            // readout -- no MouseArea, no handler anywhere in Osd.qml,
            // it auto-hides on OsdState's own timer. And a popup that
            // appears BECAUSE you are scrolling a volume/brightness key
            // is the worst possible thing to have swallow the next
            // click. It keeps its size either way, so the show/hide
            // fade+scale is untouched.
            mask: Region { width: 0; height: 0 }

            Modules.Osd { id: osd }
        }
    }

    // Low-battery alert -- see services/BatteryAlertState.qml for the
    // UPower threshold-crossing trigger logic and BatteryAlert.qml's own
    // header for why this is a separate, centered, click-to-dismiss
    // surface rather than a third OsdState "kind". Same per-screen
    // Variants/exclusionMode/aboveWindows shape as the OSD window right
    // above, for the same reasons -- but genuinely CENTERED rather than
    // anchored to an edge: no `anchors` block at all, which leaves
    // Hyprland to position the (unanchored, sized-to-content) layer
    // surface itself -- confirmed live it lands dead center, same as any
    // other anchor-less wlr-layer-shell surface.
    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: batteryAlertWindow
            required property var modelData
            screen: modelData

            focusable: false
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            aboveWindows: true

            implicitWidth: batteryAlert.width
            implicitHeight: batteryAlert.height

            // Input region, not paint state. BatteryAlert.qml hides
            // itself with `opacity: 0`, which leaves the card at its
            // full 292x292 -- and the two implicit sizes above read that
            // size regardless of whether an alert is showing, so this
            // layer surface sits 292x292 dead center on the screen at
            // all times. An unmasked wlr-layer-shell surface takes input
            // across its whole extent, so that invisible square was
            // quietly swallowing clicks in the middle of the screen:
            // reported live after a stray click there landed on the
            // "Power save mode" pill and really did switch the power
            // profile. Masking to an EMPTY region whenever there is no
            // alert lets those clicks fall through to whatever is
            // underneath, and costs the card nothing -- it keeps its
            // size, so its dismiss fade/scale still animates normally.
            mask: Region {
                width: BatteryAlertState.alertVisible ? batteryAlert.width : 0
                height: BatteryAlertState.alertVisible ? batteryAlert.height : 0
            }

            Modules.BatteryAlert { id: batteryAlert }
        }
    }

    // Notification toasts -- replaces swaync's own notification-window
    // popups. Same per-screen Variants/exclusionMode/aboveWindows shape
    // as OSD/BatteryAlert above; anchored top-left with swaync's own
    // margins (positionX/positionY: "left"/"top" in swaync/config.json --
    // that pair only ever governed TOAST position, unlike the
    // control-center below). Always mapped, like OSD, so
    // NotificationCard's own state can drive fades later without a
    // window remap; content is simply empty/zero-height when
    // NotificationState.toastQueue is empty.
    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: notifToastWindow
            required property var modelData
            screen: modelData

            focusable: false
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            aboveWindows: true

            anchors { top: true; left: true }
            // Nudged down/right to sit INSIDE the top-left tile instead
            // of straddling its frame -- asked for: "descend un peu en
            // bas à droite pour qu'elles ne coupent pas la bordure de la
            // tuile du dessous". `exclusionMode: Ignore` above means this
            // surface is placed against the raw monitor edge, NOT below
            // the bar's exclusive zone, so the old top:8/left:3 put the
            // card over the bar AND across the tile's border lines, which
            // then read as interrupted where the card covered them.
            //
            // Where that tile actually starts, on this setup:
            //   top  = 24 (bar exclusive zone) + 10 (gaps_out.top)
            //          +  3 (border_size)      = 37
            //   left =  8 (gaps_out.left)      +  3 (border_size) = 11
            // (all three from hypr/hyprland.lua). +9 past each clears the
            // rounding=12 corner arc too, so the frame stays unbroken all
            // the way around the card rather than just along the straight
            // runs. Hardcoded like the numbers it replaces -- Hyprland's
            // gaps/border aren't queryable from here -- so if gaps_out,
            // border_size or the bar's height change, these follow.
            margins { top: 46; left: 20 }

            // FIXED size, where this used to track the stack's own height.
            // A card leaving now animates for 180ms AFTER its model row is
            // gone (see NotificationToast.qml's `remove` transition), and
            // the stack's contentHeight drops the instant that row goes --
            // so a surface sized off it would shrink out from under the
            // very animation it is meant to be showing, guillotining the
            // bottom card mid-exit. Tall enough for maxToasts (4) cards at
            // their realistic worst (two body lines plus an action row).
            implicitWidth: toastStack.cardWidth
            implicitHeight: 640

            // ...which then has to be masked, or that fixed 640x340 of
            // mostly-empty transparent surface would eat clicks meant for
            // the window underneath. Same input-region trick as
            // batteryAlertWindow above: the region covers only what the
            // stack currently fills, and collapses to nothing (fully
            // click-through) when there are no toasts at all.
            mask: Region {
                width: toastStack.cardWidth
                height: toastStack.contentHeight
            }

            Modules.NotificationToast {
                id: toastStack
                anchors.fill: parent
            }
        }
    }

    // Notification center used to live here, as its own separate
    // PanelWindow + HyprlandFocusGrab (positioned under METRICS,
    // reveal-animated by hand). Gone now -- it's a `Modules.
    // NotificationCenter` drawer entry on `toolsIsland` instead (see
    // that DrawerIsland instantiation above), closed via the same
    // Hyprland raw-event listener that already dismisses the keybinds
    // sheet (see the `Connections { target: Hyprland }` block near the
    // top of this file). Same reasoning as Veille/Keybindings already
    // living inside this window rather than in their own: one fewer
    // layer-shell surface, one fewer place to keep animation timing in
    // sync by hand.
}
