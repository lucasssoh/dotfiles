#!/usr/bin/env bash
set -euo pipefail

# =========================================================
# hdr.sh — per-screen SDR/HDR toggle for Hyprland
#
#   hdr.sh toggle          -> toggles the screen under the cursor (the bar
#                             that was clicked), falling back to the focused one
#   hdr.sh debug [monitor] -> what is configured and negotiated for HDR
#
# The bar reads the HDR state itself (services/HdrState.qml); this script
# only switches it.
# =========================================================

# ---- Settings ------------------------------------------------
# HDR tuning (SDRBRIGHTNESS/SDR_WHITE_LUMINANCE/MAX_LUMINANCE/...) and the
# last-choice persistence (hdr_last_choice/hdr_save_choice) live in
# hdr-settings.sh, shared with scripts/workspace-manager.sh -- it needs the
# exact same values to reapply whichever of HDR/SDR the user last picked
# for a screen, instead of always resetting it to SDR on reload/hotplug.
source "$HOME/.config/hypr/scripts/hdr-settings.sh"

CACHE_DIR="${XDG_RUNTIME_DIR:-/tmp}/hdr-toggle"

# ---- Helpers -------------------------------------------------

focused() {
    hyprctl monitors -j | jq -r '.[] | select(.focused==true) | .name'
}

# Screen located under the cursor (= the bar that was just clicked)
monitor_at_cursor() {
    local pos cx cy
    pos=$(hyprctl cursorpos 2>/dev/null | tr -d ' ') || return 1
    cx=${pos%%,*}; cy=${pos##*,}
    [[ -z "$cx" || -z "$cy" ]] && return 1
    hyprctl monitors -j | jq -r --argjson x "$cx" --argjson y "$cy" '
        .[] | select(
            ($x >= .x) and ($x < (.x + (.width / .scale))) and
            ($y >= .y) and ($y < (.y + (.height / .scale)))
        ) | .name' | head -n1
}

# True if the screen is currently in HDR (10-bit pipeline active)
is_hdr() {
    local m="$1" fmt
    fmt=$(hyprctl monitors -j | jq -r --arg m "$m" \
        '.[] | select(.name==$m) | .currentFormat')
    [[ "$fmt" == *2101010* ]]
}

# HDR support as declared in the EDID — cached (the EDID doesn't change).
# edid-decode missing / EDID not found -> treated as capable (we don't block).
hdr_capable() {
    local m="$1" cache="$CACHE_DIR/cap-$m" edid="" path cap=1
    if [[ -f "$cache" ]]; then
        [[ "$(cat "$cache")" == "1" ]]; return
    fi
    mkdir -p "$CACHE_DIR"
    for path in /sys/class/drm/*-"$m"/edid; do
        [[ -e "$path" ]] && { edid="$path"; break; }
    done
    if [[ -n "$edid" ]] && command -v edid-decode >/dev/null 2>&1; then
        if edid-decode "$edid" 2>/dev/null \
             | grep -qiE 'HDR Static Metadata|SMPTE ST ?2084|ST2084'; then
            cap=1
        else
            cap=0
        fi
    fi
    echo "$cap" > "$cache"
    [[ "$cap" == "1" ]]
}

# Applies HDR or SDR while preserving the current mode/position/scale
#
# NB: this setup loads its config through a custom Lua binding (hl.*),
# which switches Hyprland to a "non-legacy" parser where `hyprctl keyword`
# is rejected ("keyword can't work with non-legacy parsers. Use eval.").
# We drive it via `hyprctl eval '<lua hl.*>'` instead (same pattern as
# scripts/workspace-manager.sh).
apply() {
    local m="$1" want="$2" j w h rr x y scale mode position desc
    j=$(hyprctl monitors -j | jq -r --arg m "$m" '.[] | select(.name==$m)')
    w=$(jq -r '.width'        <<<"$j")
    h=$(jq -r '.height'       <<<"$j")
    rr=$(jq -r '.refreshRate' <<<"$j")
    x=$(jq -r '.x'            <<<"$j")
    y=$(jq -r '.y'            <<<"$j")
    scale=$(jq -r '.scale'    <<<"$j")
    desc=$(jq -r '.description // empty' <<<"$j")
    rr=$(LC_NUMERIC=C printf '%.2f' "$rr")  # FR locale = decimal comma, breaks the "W x H@RR" format
    mode="${w}x${h}@${rr}"
    position="${x}x${y}"

    hyprctl eval "hl.monitor({ output = \"$m\", mode = \"$mode\", position = \"$position\", scale = ${scale}, $(hdr_extra_clause "$want") })"
    # Persists the choice (keyed by description, survives connector renames)
    # so workspace-manager.sh reapplies it instead of resetting to SDR on
    # the next hyprland.start/config.reloaded/monitor.added/removed.
    hdr_save_choice "$desc" "$want"
}

# Prints what's actually configured/negotiated for HDR, to compare against
# what Windows does before tuning anything. The "ColorManagement min/max/cll/
# fall" line (what actually gets sent to the panel per-frame) only appears in
# Hyprland's log when debug:disable_logs = false and only at Log::TRACE
# level -- if it's missing below, that line isn't being emitted at the
# current log level, not that HDR is inactive.
cmd_debug() {
    local m="${1:-$(focused)}"
    [[ -z "$m" ]] && { echo "no monitor" >&2; exit 1; }

    echo "== hyprctl monitor state ($m) =="
    hyprctl monitors -j | jq -r --arg m "$m" \
        '.[] | select(.name==$m) | {currentFormat, colorManagementPreset, sdrBrightness, sdrSaturation, sdrMinLuminance, sdrMaxLuminance}'

    echo
    echo "== EDID HDR static metadata =="
    local edid
    for edid in /sys/class/drm/*-"$m"/edid; do
        [[ -e "$edid" ]] || continue
        if command -v edid-decode >/dev/null 2>&1; then
            edid-decode "$edid" 2>/dev/null | grep -iA4 "HDR Static Metadata Data Block"
        fi
        break
    done

    echo
    echo "== last ColorManagement line(s) sent to the panel (hyprland.log, TRACE) =="
    local log
    log=$(ls -t "${XDG_RUNTIME_DIR:-/tmp}"/hypr/*/hyprland.log 2>/dev/null | head -n1)
    if [[ -z "$log" ]]; then
        echo "no hyprland.log found"
    else
        grep "ColorManagement min" "$log" | tail -n5 || echo "(no match -- enable debug:disable_logs = false to see this)"
    fi
}

# ---- Subcommands ------------------------------------------

cmd_toggle() {
    # The screen under the cursor = the bar that was clicked; falls back to focused
    local m; m=$(monitor_at_cursor) || true
    [[ -z "$m" ]] && m=$(focused)
    [[ -z "$m" ]] && exit 0
    if ! hdr_capable "$m"; then
        notify-send "HDR" "$m does not support HDR"
        exit 0
    fi
    if is_hdr "$m"; then apply "$m" sdr; else apply "$m" hdr; fi
}

# ---- Dispatch ------------------------------------------------
case "${1:-}" in
    toggle) cmd_toggle ;;
    debug)  cmd_debug "${2:-}" ;;
    *)      echo "usage: $0 {toggle|debug [monitor]}" >&2; exit 1 ;;
esac
