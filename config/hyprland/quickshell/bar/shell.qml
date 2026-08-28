import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import "modules" as Modules
import "modules/veille"
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
            // Has to stay >= the island's own height (below) and >= metrics/
            // tools' own bottom extent (3 top gap + their content, ~27) or
            // whichever pill is taller gets clipped by the surface's own
            // bounds. The main bar's Row stays flush at y:0 regardless
            // (anchors.top), only metrics/tools use the extra space.
            implicitHeight: 31

            // ── ONE BAR ───────────────────────────────────────
            // Clock + Workspaces sit dead center of the screen and never
            // move -- ActiveWindow and Media (mpris) grow OUTWARD away
            // from that fixed center point, asked for. The previous
            // approach (a single Row inside one Block, horizontalCenter-
            // anchored) kept the BLOCK's own center fixed, but Clock/
            // Workspaces still visibly shifted whenever ActiveWindow --
            // to their left in that Row -- changed width, since Row lays
            // everything out sequentially from its left edge. Now
            // centerRow is anchored straight to the screen's
            // horizontalCenter and nothing else in here can move it;
            // leftGroup/rightGroup are anchored OFF centerRow's own edges
            // (not off each other, not off a screen edge), so their
            // growth only ever extends away from the center, never
            // toward it. The background (still Modules.Block, for its
            // shared corner-radius/color logic) has no content of its
            // own any more -- its x/width are bound straight to
            // leftGroup/rightGroup's actual on-screen extents instead of
            // Block's usual Row-implicitWidth auto-sizing, so the one
            // visible pill still reads as a single shape spanning
            // window ⟷ mpris with clock/workspaces floating, unmoving,
            // in the middle of it.
            Item {
                id: barRow
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                // 24 -> 27 -> 31: first pass matched metrics/tools' own
                // bottom edge (27); this one grows past it on purpose --
                // asked for, "presque toucher les fenêtres du dessous" --
                // exclusiveZone (below, unchanged at 24) is what actually
                // reserves space from tiled windows, not this height, so
                // growing it further is purely visual (aboveWindows paints
                // over the extra few px, gaps_out.top still leaves a sliver
                // before real window content). metrics/tools deliberately
                // NOT touched -- they stay their own size, just now sit
                // shorter than the island instead of matching it exactly.
                height: 31

                Row {
                    id: centerRow
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 0
                    Modules.Clock {}
                    Modules.Workspaces { monitor: Hyprland.monitorFor(bar.screen) }
                }

                // ActiveWindow -- right edge anchored to centerRow's left
                // edge (fixed 6px gap), so growth only ever extends the
                // LEFT edge further left. opacity 0.9 matches waybar/
                // style.css's old #window rule (the whole element, not
                // just its text).
                Item {
                    id: leftGroup
                    implicitWidth: activeWindow.implicitWidth
                    height: 24
                    anchors.right: centerRow.left
                    anchors.rightMargin: 6
                    anchors.verticalCenter: parent.verticalCenter

                    Modules.ActiveWindow {
                        id: activeWindow
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        opacity: 0.9
                        monitor: Hyprland.monitorFor(bar.screen)
                    }
                }

                // Media (mpris) -- back to its own chained group, no
                // Launchers inside any more (asked for: pulled back out
                // into its own separate floating island, see below,
                // rather than grouped in here). Mirror of leftGroup: left
                // edge anchored to centerRow's right edge, so growth only
                // ever extends the RIGHT edge further right.
                Item {
                    id: rightGroup
                    implicitWidth: media.implicitWidth
                    height: 24
                    anchors.left: centerRow.right
                    anchors.leftMargin: 6
                    anchors.verticalCenter: parent.verticalCenter

                    Modules.Media {
                        id: media
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                // The one visible pill -- see header comment above. z: -1
                // keeps it painted behind leftGroup/centerRow/rightGroup
                // even though it's declared last (default stacking order
                // in an Item is declaration order).
                //
                // Glossy OLED black now, not the old flat "#0c0c0e"
                // (asked for, "vraiment ajoute le côté 000000") -- FILL
                // only, borders/rim still deliberately untouched (see the
                // "Deliberately NOT applied to the central island"
                // comments on metrics/launchers/tools below: this island
                // stays the one pill in the bar with no GlassRim at all).
                // A vertical gradient stands in for the rim's own light-
                // catches-the-top-edge logic: a sliver of dark grey right
                // at the top eases into true black by 40% down, same
                // "glossy curved surface" read as a rim would give, just
                // baked into the fill since there's no edge to trace here.
                Modules.Block {
                    id: centerIsland
                    z: -1
                    anchors.top: parent.top
                    height: 31
                    // 10 -> 14 -> 18, asked for -- bottom corners only
                    // (flushTop still squares the top ones off against the
                    // screen edge, unaffected).
                    cornerRadius: 18
                    x: leftGroup.x
                    width: rightGroup.x + rightGroup.width - leftGroup.x
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: "#0c0c0e" }
                        GradientStop { position: 0.4; color: "#000000" }
                        GradientStop { position: 1.0; color: "#000000" }
                    }
                }

                // Second, fainter glossy catch-light toward the bottom-
                // right (asked for, "un bottomright un peu brillante
                // aussi") -- a soft RADIAL highlight, echoing the same
                // asymmetric topLeft/bottomRight pairing GlassRim uses on
                // every other pill in this bar, just baked into the fill
                // here since this island alone carries no rim to hang a
                // second light source off of. Centered just past the
                // island's own bottom-right corner and fully transparent
                // by its outer stop, so it fades out before it would ever
                // need clipping to the island's own rounded corner.
                Shape {
                    id: centerGloss
                    z: -1
                    x: centerIsland.x
                    y: centerIsland.y
                    width: centerIsland.width
                    height: centerIsland.height
                    antialiasing: true
                    preferredRendererType: Shape.CurveRenderer

                    ShapePath {
                        strokeWidth: -1
                        fillGradient: RadialGradient {
                            // Pushed just PAST the actual corner (>100%/
                            // >100%) on purpose -- only the near-left/
                            // near-top arc of the circle then falls inside
                            // the island at all, so it reads as a glow
                            // hugging the corner itself rather than a
                            // separate blob floating short of it (first
                            // pass: 0.9/1.1 with a small radius, landed
                            // visibly inboard of the real corner instead).
                            //
                            // Shrunk a lot from the first pass (2.6 ->
                            // 1.1, alpha 0x2a -> 0x1c): Media sits flush
                            // against this exact corner with NO margin of
                            // its own (rightGroup's width IS the island's
                            // own right edge), so the wider/brighter first
                            // version reached far enough inward to wash
                            // right over the mpris title -- reported as
                            // "a translucent film over media". This stays
                            // inside the rounded corner's own curve
                            // instead of spilling onto whatever content
                            // happens to be sitting there.
                            centerX: centerGloss.width * 1.05
                            centerY: centerGloss.height * 1.15
                            centerRadius: centerGloss.height * 1.1
                            focalX: centerX
                            focalY: centerY
                            GradientStop { position: 0.0; color: "#1cffffff" }
                            GradientStop { position: 1.0; color: "#00ffffff" }
                        }
                        // Matches centerIsland's own corner treatment
                        // exactly (square top -- flushTop -- rounded
                        // bottom only) instead of a plain sharp-cornered
                        // rect (reported: a faint square sliver of the
                        // glow poking out past the real rounded corner,
                        // worse under HDR's own tone curve than the
                        // gradient math alone suggested it would be).
                        // Relying on the RadialGradient's alpha reaching
                        // ~0 before the true corner was the ONLY thing
                        // keeping this contained before -- this makes it
                        // structurally impossible to overflow, whatever
                        // the gradient math does.
                        PathRectangle {
                            x: 0; y: 0
                            width: centerGloss.width
                            height: centerGloss.height
                            bottomLeftRadius: centerIsland.cornerRadius
                            bottomRightRadius: centerIsland.cornerRadius
                        }
                    }
                }

                // The GlassRim edge every other pill in this bar gets,
                // added here too despite the earlier note above
                // ("Deliberately NOT applied to the central island") --
                // that pass was before the glossy-black fill existed,
                // worth re-checking now rather than trusting the old
                // verdict forever. `topOverflow` (> cornerRadius) pushes
                // the traced rect's top edge above the bar entirely, so
                // only the bottom arc -- the one edge this flush-top
                // island actually has -- ever paints, same trick
                // Block.qml's own `flushTop` documents.
                //
                // SYMMETRIC light from directly below (asked for -- a
                // single corner hotspot, GlassRim's usual default, read
                // lopsided/brighter on one side than the other here),
                // not the diagonal corner-to-corner ramp every other rim
                // in this bar uses: `hSpan: 0` removes the horizontal
                // axis from the gradient entirely, leaving a pure
                // vertical fade that's IDENTICAL at every x position --
                // `lightOrigin`'s left/right choice becomes irrelevant
                // once hSpan is 0 (only `_fromBottom` still matters),
                // kept as bottomLeft arbitrarily. `strength: 0.6`, not
                // the default 1.0 -- asked for "léger" (slight), a subtle
                // grey line rather than a bright highlight.
                //
                // cornerRadius is centerIsland's own radius MINUS 1, not
                // an exact match (reported separately: at the bright
                // corner, a sliver of the black fill's own corner still
                // showed past the rim's curve) -- a BIGGER radius cuts
                // the corner further FROM the true corner point, not
                // closer to it, so matching the fill's nominal radius
                // exactly was the wrong direction: the ring needs to
                // trace a SMALLER radius than the fill so its own curve
                // reaches at least as close to the true corner as the
                // fill's actual rendered shape does (Rectangle's native
                // per-corner rounding and Shape/PathRectangle's own
                // rounding don't trace pixel-identical curves at the
                // same nominal radius).
                Modules.GlassRim {
                    target: centerIsland
                    cornerRadius: centerIsland.cornerRadius - 1
                    lightOrigin: "bottomLeft"
                    hSpan: 0
                    // Lightened further and darkened (asked for): 0.6 ->
                    // 0.35 strength, and the highlight itself swapped
                    // from GlassRim's default near-white "#e5e5ea" to a
                    // plain mid-grey "#8e8e93" (the same tone GlassRim's
                    // OWN second ramp stop already uses elsewhere) --
                    // even at its brightest point this line no longer
                    // approaches white, just a dim grey trace.
                    strength: 0.35
                    highlightColor: "#8e8e93"
                    topOverflow: centerIsland.cornerRadius + 6
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

                // Notification bell, moved here from the main bar's far
                // left (was next to Media), asked for.
                Modules.StreamModule {
                    watchCommand: ["swaync-client", "--subscribe-waybar"]
                    watchIsData: true
                    minWidth: 40
                    clickCommand: ["bash", "-c", "$HOME/.config/waybar/scripts/swaync-toggle.sh"]
                    rightClickCommand: ["swaync-client", "-d", "-sw"]
                    // ph-bell-ringing / ph-bell / ph-bell-z (Phosphor's "sleeping
                    // bell" -- an actual semantic match for do-not-disturb,
                    // better than reusing a plain bell) / ph-bell-slash
                    // (inhibited = notifications actively blocked, distinct
                    // from dnd's "quieted"). Phosphor has no compound "dnd +
                    // inhibited" glyph the way the old Nerd Font set did --
                    // both dnd-inhibited variants fall back to bell-slash,
                    // same shape as plain inhibited; classColors below still
                    // carries the has-notification distinction.
                    classIcons: ({
                        "notification": "",
                        "none": "",
                        "dnd-notification": "",
                        "dnd-none": "",
                        "inhibited-notification": "",
                        "inhibited-none": "",
                        "dnd-inhibited-notification": "",
                        "dnd-inhibited-none": ""
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
                // Moved here from Network.qml in TOOLS (asked for) --
                // the download-rate half of what used to be one combined
                // wifi/rate module, now grouped with METRICS' other
                // continuously-updating stats instead.
                Modules.Traffic {}

                Item { width: 6; height: 1 }

                Modules.Battery {}
            }

            // Launchers -- its own separate floating island (asked for:
            // out of the central island entirely, and placed in front of
            // TOOLS rather than trailing the island). Right edge anchored
            // to TOOLS' own left edge (needs `id: tools` below) instead
            // of chasing the island's dynamic width -- sits at a stable
            // position relative to the screen's right edge, same as
            // METRICS/TOOLS themselves, rather than sliding around
            // whenever ActiveWindow/Media/workspaces resize.
            Modules.Block {
                id: launchers
                anchors.top: parent.top
                anchors.topMargin: 3
                anchors.right: tools.left
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
            // fill).
            Modules.Block {
                id: tools
                anchors.top: parent.top
                anchors.topMargin: 3
                anchors.right: parent.right
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

                    // Left/right breathing room -- asked for, left
                    // especially (Block.qml's own Row has zero built-in
                    // padding, content starts flush at x:0, and
                    // ScriptModule's own centering math wasn't enough to
                    // clear the pill's rounded left edge on its own).
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
                        Modules.Ethernet {}
                    }

                    Item { width: 6; height: 1 }

                    // Performance profile + power, moved here from the main
                    // bar (were next to notif/clock/workspaces), asked for:
                    // now sit right of connectivity in this pill instead.
                    Modules.Performance {}

                    Item {
                        implicitWidth: 28
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

                    Item { width: 2; height: 1 }
                }

            // Gradient edges for the three translucent pills. Siblings,
            // not children: Block reparents anything nested inside it
            // into its content Row (see modules/GlassRim.qml). Declared
            // after all three so they paint on top of their fills.
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
            Modules.GlassRim { target: tools }
            Modules.GlassRim { target: tools; lightOrigin: "bottomRight"; strength: 0.45 }
        }
    }

    // Sleep-awareness clock overlay -- see modules/veille/Veille.qml and
    // the project plan (temporal-drifting-hippo.md). Single instance, not
    // inside the Variants above: unlike the bar itself, this isn't
    // per-screen content, and zenMode is threaded in exactly the way
    // ActiveWindow.qml's `monitor` property is (a plain pass-through, no
    // singleton needed for one consumer).
    Veille {
        zenMode: shell.zenMode
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
    // scale Behavior can actually fade it, not just pop -- no
    // exclusiveZone set, it never reserves space from tiled windows.
    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: osdWindow
            required property var modelData
            screen: modelData

            focusable: false
            color: "transparent"

            anchors { bottom: true }
            margins.bottom: 48
            implicitWidth: osd.width
            implicitHeight: osd.height

            Modules.Osd { id: osd }
        }
    }
}
