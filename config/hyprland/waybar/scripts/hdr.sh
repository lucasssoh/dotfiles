#!/usr/bin/env bash
set -euo pipefail

# =========================================================
# hdr.sh — per-screen SDR/HDR toggle for Hyprland + Waybar
#
#   hdr.sh status   -> JSON for the waybar module (THIS bar's screen)
#   hdr.sh toggle    -> toggles the screen under the cursor (bar that was clicked)
#   hdr.sh menu      -> rofi menu (HDR-capable screens only)
#
# In "per-screen" mode, each Waybar instance displays and controls ITS
# OWN screen (via WAYBAR_OUTPUT_NAME for display, and cursor position
# for clicks — WAYBAR_OUTPUT_NAME isn't reliable in click handlers).
# =========================================================

# ---- Settings ------------------------------------------------
# HDR tuning (SDRBRIGHTNESS/SDR_WHITE_LUMINANCE/MAX_LUMINANCE/...) and the
# last-choice persistence (hdr_last_choice/hdr_save_choice) live in
# hdr-settings.sh, shared with scripts/workspace-manager.sh -- it needs the
# exact same values to reapply whichever of HDR/SDR the user last picked
# for a screen, instead of always resetting it to SDR on reload/hotplug.
source "$HOME/.config/hypr/scripts/hdr-settings.sh"

WAYBAR_SIGNAL=3         # must match "signal" in config.jsonc
RASI="$HOME/.config/rofi/theme.rasi"   # menu theme (adjust if needed)
ICON=""               # screen glyph (nf-md-monitor)

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

refresh_bar() { pkill -RTMIN+"$WAYBAR_SIGNAL" waybar 2>/dev/null || true; }

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

cmd_status() {
    # THIS bar's screen; falls back to the focused one if run by hand
    local m="${WAYBAR_OUTPUT_NAME:-$(focused)}"
    if [[ -z "$m" ]]; then
        printf '{"text":"%s","class":"hdr-na","tooltip":"No display"}\n' "$ICON"
        return
    fi
    if ! hdr_capable "$m"; then
        printf '{"text":"%s n/a","class":"hdr-na","tooltip":"%s does not support HDR"}\n' "$ICON" "$m"
    elif is_hdr "$m"; then
        printf '{"text":"%s hdr","class":"hdr-on","tooltip":"HDR active · %s\\nClick: switch to SDR · Right-click: pick a display"}\n' "$ICON" "$m"
    else
        printf '{"text":"%s sdr","class":"hdr-off","tooltip":"SDR · %s\\nClick: enable HDR · Right-click: pick a display"}\n' "$ICON" "$m"
    fi
}

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
    refresh_bar
}

cmd_menu() {
    local m rows=() state
    while read -r m; do
        [[ -z "$m" ]] && continue
        hdr_capable "$m" || continue
        if is_hdr "$m"; then state="●  HDR on"; else state="○  HDR off"; fi
        rows+=("$m  $state")
    done < <(hyprctl monitors -j | jq -r '.[].name')

    if [[ ${#rows[@]} -eq 0 ]]; then
        notify-send "HDR" "No HDR-capable display detected"
        exit 0
    fi

    local choice target
    choice=$(printf '%s\n' "${rows[@]}" \
        | rofi -dmenu -theme "$RASI" -p "HDR" -no-custom -format s -i)
    [[ -z "$choice" ]] && exit 0

    target=${choice%%[[:space:]]*}
    if is_hdr "$target"; then apply "$target" sdr; else apply "$target" hdr; fi
    refresh_bar
}

# ---- Dispatch ------------------------------------------------
case "${1:-status}" in
    status) cmd_status ;;
    toggle) cmd_toggle ;;
    menu)   cmd_menu ;;
    debug)  cmd_debug "${2:-}" ;;
    *)      echo "usage: $0 {status|toggle|menu|debug [monitor]}" >&2; exit 1 ;;
esac
