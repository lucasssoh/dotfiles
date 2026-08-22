#!/usr/bin/env bash
set -euo pipefail

# =========================================================
# workspace-manager.sh — single engine: active screens, position,
# alignment, and max refresh rate, resolved BY ROLE (never by
# connector name — names can change between plugs, e.g. DP-2 becoming
# DP-9 mid-session). The external screen is always set to SDR here:
# HDR is never auto-applied, it's a manual choice via
# waybar/scripts/hdr.sh (see below).
#
#   Internal = 1st monitor whose name matches eDP*/LVDS*/DSI*
#   External = 1st remaining monitor, in `hyprctl monitors` order
#
#   Workspaces 1-5  -> the MAIN screen      (or the sole active one, if only one is)
#   Workspaces 6-10 -> the SECONDARY screen (ditto)
#
# Split evenly (5/5, not the old 7/3) -- no reason one screen should get
# more slots than the other by default.
#
# "Main" is not hardcoded to internal: it's whichever screen was last used
# SOLO (mode "internal" or "external"), tracked as `main` in the state
# file below and flipped automatically by display-layout.sh every time a
# single-screen mode is chosen. Asked for: a whole session spent in
# external-only mode already spreads windows across the full 1-10 range
# on that one screen -- reconnecting internal and going back to "both"
# used to always reclaim 1-5 for internal regardless of that, forcing a
# manual re-shuffle of everything just opened in 1-5 over to 6-10. Now
# "both" keeps 1-5 on whichever screen was actually main a moment ago.
#
# The desired layout (which screens to use, which one is on the left,
# how they align, which one is main) is read from a persistent JSON
# state — same pattern as the wallpaper system (set_wallpaper.sh /
# restore_wallpaper.sh + wallpaper-playlist.json):
#
#   ~/.config/hypr/display-layout.json
#   { "mode": "both"|"internal"|"external",
#     "position": "external-left"|"external-right",
#     "align": "center"|"top"|"bottom",
#     "main": "internal"|"external" }
#
# Written by scripts/display-layout.sh (rofi menu / waybar module).
# Absent or invalid -> defaults to both / external-left / center / internal.
#
# Idempotent: only replays deterministic `hyprctl eval` calls from the
# current state + the JSON file — safe to rerun with no side effect.
# Called by the hyprland.start / config.reloaded / monitor.added /
# monitor.removed hooks (hypr/hyprland.lua).
#
# NB: this setup loads its config via a custom Lua binding (hl.*),
# which switches Hyprland to a "non-legacy" parser where `hyprctl
# keyword` is refused ("keyword can't work with non-legacy parsers.
# Use eval."). Everything is therefore driven via
# `hyprctl eval '<lua hl.*>'`, which calls exactly the same functions
# as hypr/monitors.lua.
# =========================================================

STATE_FILE="$HOME/.config/hypr/display-layout.json"
SCALE_FILE="$HOME/.config/hypr/scale.json"

# ---- Desired layout (persistent state, defaults if absent/invalid) ----
layout_mode="both"
layout_position="external-left"
layout_align="center"
layout_main="internal"
if [[ -f "$STATE_FILE" ]]; then
    v="$(jq -r '.mode // empty'     "$STATE_FILE" 2>/dev/null || true)"
    if [[ "$v" =~ ^(both|internal|external)$ ]]; then layout_mode="$v"; fi
    v="$(jq -r '.position // empty' "$STATE_FILE" 2>/dev/null || true)"
    if [[ "$v" =~ ^(external-left|external-right)$ ]]; then layout_position="$v"; fi
    v="$(jq -r '.align // empty'    "$STATE_FILE" 2>/dev/null || true)"
    if [[ "$v" =~ ^(center|top|bottom)$ ]]; then layout_align="$v"; fi
    v="$(jq -r '.main // empty'     "$STATE_FILE" 2>/dev/null || true)"
    if [[ "$v" =~ ^(internal|external)$ ]]; then layout_main="$v"; fi
fi

# ---- Desired per-screen scale (persistent state, defaults if absent/invalid) ----
# { "internal": "1", "external": "1.25" } -- written by hand for now, no
# menu/dispatcher wired to this file yet.
int_scale="1"
ext_scale="1"
if [[ -f "$SCALE_FILE" ]]; then
    v="$(jq -r '.internal // empty' "$SCALE_FILE" 2>/dev/null || true)"
    if [[ "$v" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then int_scale="$v"; fi
    v="$(jq -r '.external // empty' "$SCALE_FILE" 2>/dev/null || true)"
    if [[ "$v" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then ext_scale="$v"; fi
fi

# ---- All connected monitors, including disabled ones ----------------
# ("monitors -j" alone EXCLUDES disabled screens — needed to resolve
# roles/modes even when a screen was turned off by a previous mode
# choice.)
mons_json="$(hyprctl monitors all -j)"

# ---- Role resolution ------------------------------------------------------

# Internal panel connector read from DRM rather than via `hyprctl
# monitors`, which loses the panel as soon as it's offline. Reading from
# DRM avoids the fallback below misclassifying the external screen as
# internal in "external only" mode (panel off, so absent from monitor
# data), which would make it impossible to switch back to the internal
# display. Dynamic resolution (follows the real connector, never
# hardcoded). Same helper duplicated in scripts/display-layout.sh
# (read-only, for menu display).
internal_from_drm() {
    local d
    # 1) CONNECTED internal connector = this boot's real panel. Handles the
    #    dual-GPU MUX (the panel can appear as card1-eDP-* or card2-eDP-*
    #    depending on the routing chosen at boot): checking the status is
    #    necessary, since the glob's first connector can be a ghost
    #    connector from a GPU not used this boot.
    for d in /sys/class/drm/card*-eDP-* /sys/class/drm/card*-LVDS-* /sys/class/drm/card*-DSI-*; do
        [[ -e "$d" ]] || continue
        [[ "$(cat "$d/status" 2>/dev/null)" == connected ]] || continue
        basename "$d" | sed -E 's/^card[0-9]+-//'
        return 0
    done
    # 2) Fallback: any internal connector, even disabled — avoids getting
    #    stuck in "external only" mode (panel off, absent from the first
    #    pattern above, but still ours).
    for d in /sys/class/drm/card*-eDP-* /sys/class/drm/card*-LVDS-* /sys/class/drm/card*-DSI-*; do
        [[ -e "$d" ]] || continue
        basename "$d" | sed -E 's/^card[0-9]+-//'
        return 0
    done
}

internal="$(internal_from_drm)"
if [[ -z "$internal" ]]; then
    internal="$(jq -r '[.[] | select(.name | test("^(eDP|LVDS|DSI)"))][0].name // empty' <<<"$mons_json")"
fi
if [[ -z "$internal" ]]; then
    # No laptop panel detected (desktop machine): fall back to the 1st listed monitor
    internal="$(jq -r '.[0].name // empty' <<<"$mons_json")"
fi
[[ -z "$internal" ]] && { echo "workspace-manager: aucun moniteur détecté" >&2; exit 0; }

first_external="$(jq -r --arg m "$internal" '[.[] | select(.name != $m)][0].name // empty' <<<"$mons_json")"

# ---- Resolving active screens from the desired mode (+ guards) ---
active_internal=true
active_external=true
case "$layout_mode" in
    internal) active_external=false ;;
    external) active_internal=false ;;
esac
[[ -z "$first_external" ]] && active_external=false   # no external connected -> can't be active
if [[ "$active_internal" != true && "$active_external" != true ]]; then
    active_internal=true   # never zero active screens: fall back to internal
fi

# ---- Workspace target monitors (1-5 / 6-10) -- computed here (used to
#      live only at the bottom) because the migration step below needs
#      it BEFORE the monitor enable/disable dance runs. Which real
#      screen gets which range now follows `layout_main` (see header
#      comment) instead of hardcoding internal = 1-5.
if [[ "$active_internal" == true && "$active_external" == true ]]; then
    if [[ "$layout_main" == "external" ]]; then
        range15_target="$first_external"; range610_target="$internal"
    else
        range15_target="$internal"; range610_target="$first_external"
    fi
elif [[ "$active_internal" == true ]]; then
    range15_target="$internal"; range610_target="$internal"
else
    range15_target="$first_external"; range610_target="$first_external"
fi

# ---- Remembers who has keyboard focus right now, to hand it back at the
#      very end -- the migration step below can steal it (see its own
#      comment on why moving a workspace also switches to it).
pre_focused_monitor="$(jq -r '.[] | select(.focused==true) | .name' <<<"$mons_json")"
pre_focused_ws="$(jq -r --arg m "$pre_focused_monitor" '.[] | select(.name==$m) | .activeWorkspace.id // empty' <<<"$mons_json")"

# ---- Helper: best available refresh rate at the screen's current
#      native resolution (never hardcoded — depends on the panel) ----
best_refresh() {
    local name="$1" w h
    w=$(jq -r --arg m "$name" '.[] | select(.name==$m) | .width'  <<<"$mons_json")
    h=$(jq -r --arg m "$name" '.[] | select(.name==$m) | .height' <<<"$mons_json")
    jq -r --arg m "$name" --argjson w "$w" --argjson h "$h" '
        .[] | select(.name==$m) | .availableModes[]?
        | select(startswith(($w|tostring) + "x" + ($h|tostring) + "@"))
        | capture("@(?<rr>[0-9.]+)Hz").rr | tonumber
    ' <<<"$mons_json" | sort -rn | head -1
}

# ---- Position / alignment (logical coordinates) -----------------------
# Scale is fixed at 1 (100%) on every screen -- see the hl.monitor() calls
# below -- so logical coordinates are just the physical pixel sizes,
# no per-role division needed.
int_w=$(jq -r --arg m "$internal" '.[] | select(.name==$m) | .width'  <<<"$mons_json")
int_h=$(jq -r --arg m "$internal" '.[] | select(.name==$m) | .height' <<<"$mons_json")
int_lw=$int_w
int_lh=$int_h
int_x=0
int_y=0

if [[ -n "$first_external" ]]; then
    ext_w=$(jq -r --arg m "$first_external" '.[] | select(.name==$m) | .width'  <<<"$mons_json")
    ext_h=$(jq -r --arg m "$first_external" '.[] | select(.name==$m) | .height' <<<"$mons_json")
    ext_lw=$ext_w
    ext_lh=$ext_h
    ext_x=0
    ext_y=0
fi

if [[ "$active_internal" == true && "$active_external" == true ]]; then
    if [[ "$layout_position" == "external-left" ]]; then
        ext_x=0; int_x=$ext_lw
    else
        int_x=0; ext_x=$int_lw
    fi
    max_h=$(( int_lh > ext_lh ? int_lh : ext_lh ))
    case "$layout_align" in
        top)    int_y=0; ext_y=0 ;;
        bottom) int_y=$(( max_h - int_lh )); ext_y=$(( max_h - ext_lh )) ;;
        *)      int_y=$(( (max_h - int_lh) / 2 )); ext_y=$(( (max_h - ext_lh) / 2 )) ;;
    esac
fi
# Only one active screen -> already x=0/y=0 by default above, nothing more to do.

# ---- Applies the internal screen (if active) --------------------------------------
if [[ "$active_internal" == true ]]; then
    best_rr="$(best_refresh "$internal")"
    int_mode="preferred"
    [[ -n "$best_rr" ]] && int_mode="${int_w}x${int_h}@${best_rr}"
    hyprctl eval "hl.monitor({ output = \"$internal\", disabled = false, mode = \"$int_mode\", position = \"${int_x}x${int_y}\", scale = $int_scale })" >/dev/null
fi

# ---- Applies the external screen (if active): max refresh, always SDR -------
# SDR is ALWAYS the default here (desktop, startup, reload, hotplug): HDR
# is never auto-applied, since it would skew the colors of any non-HDR
# content. HDR is a strictly manual user choice, turned on on demand for
# media content via the dedicated waybar module (waybar/scripts/hdr.sh
# toggle/menu) — independent from this script.
if [[ "$active_external" == true ]]; then
    best_rr="$(best_refresh "$first_external")"
    ext_mode="preferred"
    [[ -n "$best_rr" ]] && ext_mode="${ext_w}x${ext_h}@${best_rr}"
    hyprctl eval "hl.monitor({ output = \"$first_external\", disabled = false, mode = \"$ext_mode\", position = \"${ext_x}x${ext_y}\", scale = $ext_scale, bitdepth = 8, cm = \"auto\" })" >/dev/null
fi

# ---- Force-migrates already-open workspaces to their new target monitor,
#      BEFORE the losing monitor gets disabled below ---------------------
# hl.workspace_rule() (below) only sets a PREFERENCE for where a
# workspace opens in the FUTURE -- it doesn't reliably drag an already-
# populated workspace's live windows over the moment the rule changes.
# That gap is exactly the "fenêtres perdues/mal placées" bug: toggling
# both -> internal-only -> both with windows already open flipped a
# workspace's rule to a new monitor, but its real content stayed parked
# on the old one (or wherever Hyprland's own disconnect-time fallback put
# it) until something else forced a resync. Same "don't trust the rule
# alone" lesson compact-workspaces.sh already learned for individual
# windows (see its own header comment) -- hl.dsp.workspace.move()
# (-> native moveworkspacetomonitor) instead relocates it right now,
# deterministically.
#
# Runs here, with both monitors still enabled, specifically so a
# workspace can be moved OFF the monitor that's about to be disabled a
# few lines down -- moving it after that disable would mean relying on
# Hyprland's own disconnect-time reassignment instead, which is exactly
# what isn't trusted here.
#
# Guarded to real work only: skips workspaces that don't exist yet,
# already sit on their target, or hold no real (non-dashboard) windows --
# an ordinary reload/reassert with nothing to migrate shouldn't yank
# focus or flicker a monitor for no reason.
workspaces_json="$(hyprctl workspaces -j)"
clients_json="$(hyprctl clients -j)"

migrate_workspace_if_needed() {
    local ws="$1" target="$2" cur has_windows
    cur="$(jq -r --argjson w "$ws" '.[] | select(.id==$w) | .monitor' <<<"$workspaces_json")"
    [[ -z "$cur" || "$cur" == "$target" ]] && return 0
    has_windows="$(jq -r --argjson w "$ws" \
        '[.[] | select(.workspace.id==$w and (.class | ascii_downcase | contains("dashboard") | not))] | length' \
        <<<"$clients_json")"
    [[ "$has_windows" -eq 0 ]] && return 0
    hyprctl eval "hl.dispatch(hl.dsp.workspace.move({ workspace = $ws, monitor = \"$target\" }))" >/dev/null
}

for i in 1 2 3 4 5; do migrate_workspace_if_needed "$i" "$range15_target"; done
for i in 6 7 8 9 10; do migrate_workspace_if_needed "$i" "$range610_target"; done

# ---- Turns off the unwanted screen, AFTER activating the others ----------
# CRITICAL ORDER: disabling before enabling can momentarily pass through
# zero active screens (e.g. switching external-only -> internal-only),
# which makes Hyprland fall back to its headless fallback. On this 0.55.3
# build, this fallback causes a SEGV (see hyprlandCrashReport4932.txt:
# applyMonitorRule -> onDisconnect -> enterUnsafeState -> CHeadlessOutput::
# commit -> SEGV). Enabling first guarantees at least one screen stays
# active at all times.
[[ "$active_internal" != true ]] && \
    hyprctl eval "hl.monitor({ output = \"$internal\", disabled = true })" >/dev/null
[[ -n "$first_external" && "$active_external" != true ]] && \
    hyprctl eval "hl.monitor({ output = \"$first_external\", disabled = true })" >/dev/null

# ---- Workspace assignment (1-5 / 6-10) -- range15_target/range610_target
#      were already resolved near the top (see comment there).
apply_workspace_rule() {
    local ws="$1" mon="$2"
    hyprctl eval "hl.workspace_rule({ workspace = \"$ws\", monitor = \"$mon\", persistent = true })" >/dev/null
}

for i in 1 2 3 4 5; do apply_workspace_rule "$i" "$range15_target"; done
for i in 6 7 8 9 10; do apply_workspace_rule "$i" "$range610_target"; done

# ---- Nudges Quickshell's workspace/monitor cache -----------------------
# Same quirk as compact-workspaces.sh (see its own comment on this exact
# line): hl.workspace_rule()/hl.monitor(), driven via `hyprctl eval`, don't
# emit anything on Hyprland's normal IPC event socket. Quickshell's
# Hyprland.workspaces model DOES receive the real monitor.added/
# monitor.removed events that trigger this script in the first place (see
# hypr/hyprland.lua), but not the workspace-monitor reassignment that
# follows -- so a bar sitting on a monitor that just changed role (e.g.
# workspace 8 moving from the now-unplugged external screen back onto the
# internal one) kept showing that workspace's pill on the wrong bar, or
# not highlighting it at all, until something else forced a resync. This
# is exactly the "need SUPER+C to make multi-monitor sort itself out"
# symptom -- compact-workspaces.sh's own refreshWorkspaces call was
# fixing it as an unrelated side effect. Silently a no-op if quickshell
# isn't running/installed (still using waybar, or between sessions).
qs -c bar ipc call bar refreshWorkspaces >/dev/null 2>&1 || true

# ---- Hands focus back to whoever had it before the migration step above
#      possibly switched a monitor's visible workspace out from under it.
if [[ -n "$pre_focused_monitor" && -n "$pre_focused_ws" ]]; then
    hyprctl eval "hl.dispatch(hl.dsp.focus({ workspace = \"$pre_focused_ws\" }))" >/dev/null 2>&1 || true
fi
