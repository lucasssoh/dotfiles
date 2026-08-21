import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import "modules" as Modules
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
        }
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
            // 24 (main bar) + 3 (metrics/tools pills' own top gap) -- the
            // window itself has to be this tall or those pills (see below)
            // would get clipped by the surface's own bounds. The main
            // bar's Row stays flush at y:0 regardless (anchors.top), only
            // metrics/tools use the extra space.
            implicitHeight: 27

            // ── ONE BAR ───────────────────────────────────────
            // A single Block, not 3 separate pills glued near each other
            // -- one shape, one background, anchored by its own
            // horizontalCenter to the screen's, so ANY content change
            // anywhere inside it shifts BOTH edges outward symmetrically
            // (width grows -> left edge moves left by half, right edge
            // moves right by half, center point never moves). ActiveWindow
            // and Media (mpris) -- "les seuls vrais élargisseurs", the two
            // modules whose width genuinely swings a lot -- sit at the two
            // ends, so it's mostly their growth that's visible, but
            // literally anything in here growing has the same two-sided
            // effect, not just those two. Former cluster boundaries (what
            // used to be up to 7 separate pills) are now just 6px spacer
            // Items -- distinct groups WITHOUT a border anywhere.
            Modules.Block {
                anchors.horizontalCenter: parent.horizontalCenter
                // top, not verticalCenter -- the window is now taller
                // (implicitHeight: 27, see above) to fit the separate
                // metrics/tools pills, and this keeps the main bar flush
                // at y:0 regardless of that extra height.
                anchors.top: parent.top
                // 24 -> 27: the metrics/tools pills sit only 3px above
                // where tiled windows start, but the island (unchanged at
                // 24) had a full 6px gap there -- asked for, so all 3
                // pills now end at the same y (27) and read as one
                // consistent proximity to whatever's below, not the island
                // floating further from it than its neighbours. Row inside
                // Block.qml stays vertically centered in the extra 3px,
                // not stuck to the top.
                height: 27
                color: "#0c0c0e"

                // Far-left end -- 0 width (and thus 0 space) whenever no
                // player is active (see Media.qml's implicitWidth:
                // pill.width).
                Modules.Media { id: media }

                Item { width: 6; height: 1 }

                Modules.Clock {}
                Modules.Workspaces { monitor: Hyprland.monitorFor(bar.screen) }

                Item { width: 6; height: 1 }

                // Far-right end -- moved here from the far-left (was next
                // to notif/clock/workspaces originally), asked for: window
                // context reads better toward the outside edge. opacity
                // 0.9 matches waybar/style.css's old #window rule (the
                // whole element, not just its text).
                Modules.ActiveWindow {
                    id: activeWindow
                    opacity: 0.9
                    monitor: Hyprland.monitorFor(bar.screen)
                }
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

                // Notification bell, moved here from the main bar's far
                // left (was next to Media), asked for.
                Modules.StreamModule {
                    watchCommand: ["swaync-client", "--subscribe-waybar"]
                    watchIsData: true
                    minWidth: 40
                    clickCommand: ["bash", "-c", "$HOME/.config/waybar/scripts/swaync-toggle.sh"]
                    rightClickCommand: ["swaync-client", "-d", "-sw"]
                    classIcons: ({
                        "notification": "󱅫",
                        "none": "󰂜",
                        "dnd-notification": "󰂠",
                        "dnd-none": "󰪓",
                        "inhibited-notification": "󰂛",
                        "inhibited-none": "󰪑",
                        "dnd-inhibited-notification": "󰂛",
                        "dnd-inhibited-none": "󰪑"
                    })
                    classColors: ({
                        "notification": "#a8b4c4",
                        "dnd-notification": "#a8b4c4",
                        "inhibited-notification": "#a8b4c4",
                        "dnd-inhibited-notification": "#a8b4c4",
                        "dnd-none": "#48484a",
                        "dnd-inhibited-none": "#48484a",
                        "none": "#f2f2f7",
                        "inhibited-none": "#f2f2f7"
                    })
                }

                Item { width: 6; height: 1 }

                Modules.Cpu {}
                Modules.Temperature {}
                Modules.Fan {}
                Modules.Memory {}

                Item { width: 6; height: 1 }

                Modules.Battery {}
            }

            // ── LAUNCHERS (separate from the main bar, right of metrics) ──
            // Pulled back OUT of the tools pill into its own block, asked
            // for -- same floating treatment as METRICS/TOOLS. Position
            // asked for precisely: right of metrics, left of mpris --
            // anchored to METRICS's own right edge (id: metrics above), a
            // static position, NOT the island's left edge (tried that
            // first, moves every time mpris shows/hides -- asked to keep
            // it fixed relative to the left block instead).
            Modules.Block {
                anchors.top: parent.top
                anchors.topMargin: 3
                anchors.left: metrics.right
                anchors.leftMargin: 6
                flushTop: false
                color: "#730c0c0e"

                // Animated (see Launchers.qml's Behavior on implicitWidth)
                // even though an app opening/closing only shifts this
                // pill a little.
                Modules.Launchers {
                    opacity: 0.8
                }
            }

            // ── TOOLS (separate from the main bar, top-right) ──
            // display/hdr/connectivity/perf/power -- status/toggle
            // indicators, split from METRICS. Same floating treatment
            // (3px top gap, 6px right gap, rounded corners, translucent
            // fill).
            Modules.Block {
                anchors.top: parent.top
                anchors.topMargin: 3
                anchors.right: parent.right
                anchors.rightMargin: 6
                flushTop: false
                color: "#730c0c0e"

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

                    Modules.Hdr { monitor: Hyprland.monitorFor(bar.screen) }

                    Item { width: 6; height: 1 }

                    // Network's rate text re-measures its digit count every
                    // 2s (see Network.qml's Timer) -- deliberately NOT
                    // width-animated, so a rate-text change still just
                    // snaps this pill's width instantly instead of
                    // triggering a smooth (but then near-continuous)
                    // resize. No more #34383f contrast background behind
                    // these 4 -- asked for, sits directly on the pill's own
                    // translucent fill now, same as everything else in it.
                    Row {
                        Modules.AudioOutput {}
                        Modules.AudioInput {}
                        Modules.Bluetooth {}
                        Modules.Network {}
                    }

                    Item { width: 6; height: 1 }

                    // Performance profile + power, moved here from the main
                    // bar (were next to notif/clock/workspaces), asked for:
                    // now sit right of connectivity in this pill instead.
                    Modules.Performance {}

                    Item {
                        implicitWidth: Math.max(powerLabel.implicitWidth + 12, 28)
                        implicitHeight: 24

                        Text {
                            id: powerLabel
                            anchors.centerIn: parent
                            // 󰍃 (md-logout, "exit door") instead of ⏻ (power
                            // symbol) -- asked for. Same red, just a different
                            // glyph in it.
                            text: "󰍃"
                            color: "#ff6e6e"
                            font.family: Fonts.icon
                            font.pixelSize: 13
                        }

                        MouseArea {
                            anchors.fill: parent
                            onClicked: Quickshell.execDetached(["bash", "-c", "$HOME/.local/bin/roue power"])
                        }
                    }
                }
        }
    }
}
