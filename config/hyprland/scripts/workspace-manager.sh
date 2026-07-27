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
#   Workspaces 1-7  -> internal (or external if internal inactive)
#   Workspaces 8-10 -> external (or internal if external inactive/absent)
#
# The desired layout (which screens to use, which one is on the left,
# how they align) is read from a persistent JSON state — same pattern
# as the wallpaper system (set_wallpaper.sh / restore_wallpaper.sh +
# wallpaper-playlist.json):
#
#   ~/.config/hypr/display-layout.json
#   { "mode": "both"|"internal"|"external",
#     "position": "external-left"|"external-right",
#     "align": "center"|"top"|"bottom" }
#
# Written by scripts/display-layout.sh (rofi menu / waybar module).
# Absent or invalid -> defaults to both / external-left / center.
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
SCALE_STATE_FILE="$HOME/.config/hypr/scale.json"

# ---- Desired layout (persistent state, defaults if absent/invalid) ----
layout_mode="both"
layout_position="external-left"
layout_align="center"
if [[ -f "$STATE_FILE" ]]; then
    v="$(jq -r '.mode // empty'     "$STATE_FILE" 2>/dev/null || true)"
    if [[ "$v" =~ ^(both|internal|external)$ ]]; then layout_mode="$v"; fi
    v="$(jq -r '.position // empty' "$STATE_FILE" 2>/dev/null || true)"
    if [[ "$v" =~ ^(external-left|external-right)$ ]]; then layout_position="$v"; fi
    v="$(jq -r '.align // empty'    "$STATE_FILE" 2>/dev/null || true)"
    if [[ "$v" =~ ^(center|top|bottom)$ ]]; then layout_align="$v"; fi
fi

# ---- Desired scale by role (persistent state, defaults if absent/invalid) ----
# Written by waybar/scripts/scale.sh (per-screen module, see hdr.sh). Always
# BY ROLE, never by connector name -- same guarantees as above.
INT_SCALE="1"
EXT_SCALE="1.25"
if [[ -f "$SCALE_STATE_FILE" ]]; then
    v="$(jq -r '.internal // empty' "$SCALE_STATE_FILE" 2>/dev/null || true)"
    if [[ -n "$v" ]]; then INT_SCALE="$v"; fi
    v="$(jq -r '.external // empty' "$SCALE_STATE_FILE" 2>/dev/null || true)"
    if [[ -n "$v" ]]; then EXT_SCALE="$v"; fi
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

# ---- Position / alignment (logical coordinates = pixels ÷ scale) -----
# The internal screen is at INT_SCALE, the external one at EXT_SCALE — the
# same values that will be applied further down.
int_w=$(jq -r --arg m "$internal" '.[] | select(.name==$m) | .width'  <<<"$mons_json")
int_h=$(jq -r --arg m "$internal" '.[] | select(.name==$m) | .height' <<<"$mons_json")
int_lw=$(jq -n --argjson w "$int_w" --argjson s "$INT_SCALE" '($w / $s) | floor')
int_lh=$(jq -n --argjson h "$int_h" --argjson s "$INT_SCALE" '($h / $s) | floor')
int_x=0
int_y=0

if [[ -n "$first_external" ]]; then
    ext_w=$(jq -r --arg m "$first_external" '.[] | select(.name==$m) | .width'  <<<"$mons_json")
    ext_h=$(jq -r --arg m "$first_external" '.[] | select(.name==$m) | .height' <<<"$mons_json")
    ext_lw=$(jq -n --argjson w "$ext_w" --argjson s "$EXT_SCALE" '($w / $s) | floor')
    ext_lh=$(jq -n --argjson h "$ext_h" --argjson s "$EXT_SCALE" '($h / $s) | floor')
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
    hyprctl eval "hl.monitor({ output = \"$internal\", disabled = false, mode = \"$int_mode\", position = \"${int_x}x${int_y}\", scale = ${INT_SCALE} })" >/dev/null
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
    hyprctl eval "hl.monitor({ output = \"$first_external\", disabled = false, mode = \"$ext_mode\", position = \"${ext_x}x${ext_y}\", scale = ${EXT_SCALE}, bitdepth = 8, cm = \"auto\" })" >/dev/null
fi

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

# ---- Workspace assignment (1-7 / 8-10), folded onto the active screen --
if [[ "$active_internal" == true && "$active_external" == true ]]; then
    int_target="$internal"; ext_target="$first_external"
elif [[ "$active_internal" == true ]]; then
    int_target="$internal"; ext_target="$internal"
else
    int_target="$first_external"; ext_target="$first_external"
fi

apply_workspace_rule() {
    local ws="$1" mon="$2"
    hyprctl eval "hl.workspace_rule({ workspace = \"$ws\", monitor = \"$mon\", persistent = true })" >/dev/null
}

for i in 1 2 3 4 5 6 7; do apply_workspace_rule "$i" "$int_target"; done
for i in 8 9 10;         do apply_workspace_rule "$i" "$ext_target"; done
