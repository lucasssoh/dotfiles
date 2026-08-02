import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import "modules" as Modules

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
//   background #141414  surface #1e1e20  overlay #2c2c2e
//   overlay2   #505050  text    #f2f2f7  muted   #48484a
//   accent2    #4fefff  play    #237823  danger  #ff6e6e
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
    // happens to be globally focused (see modules/Workspaces.qml and
    // modules/Hdr.qml's `monitor` property). ActiveWindow.qml is NOT
    // per-monitor -- it still shows Hyprland.activeToplevel (the
    // globally focused window everywhere), since Hyprland doesn't expose
    // a simple "last active window on monitor X" the same way it does
    // monitorFor() -- would need to be derived from the monitor's
    // activeWorkspace's toplevels, not done here.

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

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: bar
            required property var modelData
            screen: modelData

            focusable: false
            visible: !shell.zenMode
            // Was 30 (implicitHeight + margins.top), which apparently
            // double-counted the margin -- exclusiveZone is measured
            // relative to the anchors margins already offset from, not
            // from the raw screen edge on top of that. Just the panel's
            // own height. If this overshoots/undershoots, report the
            // actual pixel gap and it can be tuned precisely instead of
            // guessed again.
            exclusiveZone: 24
            aboveWindows: true
            color: "transparent"

            anchors { top: true; left: true; right: true }
            margins { top: 6; left: 6; right: 6 }
            implicitHeight: 24

            // ── LEFT ──────────────────────────────────────────
            Row {
                id: left
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                spacing: 6

                // Block: notification + clock + workspaces (glued)
                Modules.Block {
                    color: "#141414"
                    borderColor: "#505050"

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
                            "notification": "#4fefff",
                            "dnd-notification": "#4fefff",
                            "inhibited-notification": "#4fefff",
                            "dnd-inhibited-notification": "#4fefff",
                            "dnd-none": "#48484a",
                            "dnd-inhibited-none": "#48484a",
                            "none": "#f2f2f7",
                            "inhibited-none": "#f2f2f7"
                        })
                    }

                    Modules.Clock {}
                    Modules.Workspaces { monitor: Hyprland.monitorFor(bar.screen) }
                }

                // Block: window (standalone, own @overlay border)
                // opacity 0.9 matches waybar/style.css's #window rule (the
                // whole element, not just its text)
                Modules.Block {
                    id: windowBlock
                    color: "#141414"
                    borderColor: "#2c2c2e"
                    opacity: 0.9
                    Modules.ActiveWindow { id: activeWindow }
                }
            }

            // ── CENTER ────────────────────────────────────────
            // Not wrapped in Block -- Media.qml draws its own pill so it
            // can control the open/close stretch animation directly.
            //
            // Real anti-collision, not a fixed nudge: centered within
            // whatever space is actually free between `left`'s right edge
            // and `right`'s left edge. Only `right` (Launchers, no cap --
            // more running apps can grow it arbitrarily) drives the
            // TARGET center reactively though: `left`'s live width is
            // used for the safety clamp (never actually overlap it), but
            // for the ideal/target position, ActiveWindow's own live
            // width is substituted with its known maxWidth (see
            // ActiveWindow.qml) whenever a window is shown. Window titles
            // change constantly (focus switches, page loads...) and
            // ActiveWindow is already clamped there, so reacting to its
            // LIVE width just made mpris visibly jitter left/right on
            // every title change for no real layout reason -- Launchers
            // has no such cap to substitute, so it has no such fixed
            // stand-in and stays fully live, same as before. Since
            // idealFreeStart assumes window is always at its widest, it's
            // always >= the real freeStart, so this can't by itself cause
            // an overlap with the real window chip.
            Modules.Media {
                id: media
                anchors.verticalCenter: parent.verticalCenter
                x: {
                    const freeStart = left.width;
                    const freeEnd = bar.width - right.width;
                    const windowMax = activeWindow.hasWindow ? activeWindow.maxWidth : 0;
                    const idealFreeStart = left.width - windowBlock.width + windowMax;
                    const ideal = idealFreeStart + (freeEnd - idealFreeStart - media.width) / 2;
                    return Math.max(freeStart, Math.min(ideal, freeEnd - media.width));
                }
            }

            // ── RIGHT ─────────────────────────────────────────
            Row {
                id: right
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: 6

                // Running apps -- native, clickable-per-app, see
                // modules/Launchers.qml. No wrapping Block: each chip already
                // has its own background (radius:4, @overlay), a shared
                // block background behind them all would just be a second,
                // redundant layer. opacity 0.8 still matches waybar/
                // style.css's #custom-apps rule, applied directly here now.
                Modules.Launchers {
                    opacity: 0.8
                }

                // Block: cpu + temperature + fan + memory (glued)
                Modules.Block {
                    color: "#141414"
                    borderColor: "#505050"
                    Modules.Cpu {}
                    Modules.Temperature {}
                    Modules.Fan {}
                    Modules.Memory {}
                }

                // Block: display layout + HDR (glued)
                Modules.Block {
                    color: "#141414"
                    borderColor: "#505050"

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
                            "display-internal": "#4fefff",
                            "display-external": "#4fefff"
                        })
                    }

                    Modules.Hdr { monitor: Hyprland.monitorFor(bar.screen) }
                }

                // Block: network + bluetooth + audio out + audio in (glued, @overlay)
                Modules.Block {
                    color: "#2c2c2e"
                    borderColor: "#2c2c2e"

                    Modules.Network {}
                    Modules.Bluetooth {}
                    Modules.AudioOutput {}
                    Modules.AudioInput {}
                }

                // Block: battery (standalone)
                Modules.Block {
                    color: "#141414"
                    borderColor: "#505050"
                    Modules.Battery {}
                }

                // Block: performance profile + power (glued) -- same
                // background/border as the rest of the neutral dalle
                // (workspaces, metrics, battery...) now, dropping the old
                // @surface/@overlay distinct tier.
                Modules.Block {
                    color: "#141414"
                    borderColor: "#505050"

                    Modules.Performance {}

                    Item {
                        implicitWidth: Math.max(powerLabel.implicitWidth + 12, 28)
                        implicitHeight: 24

                        Text {
                            id: powerLabel
                            anchors.centerIn: parent
                            text: "⏻"
                            color: "#ff6e6e"
                            font.family: "JetBrains Mono"
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
}
