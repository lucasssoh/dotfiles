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
SDRBRIGHTNESS="1.0"     # SDR content brightness while the screen is in HDR (1.0..2.0)
SDRSATURATION="1.0"     # SDR content saturation in HDR
SDR_WHITE_LUMINANCE="220"  # SDR white level inside the HDR container (Hyprland default: 80)
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
    local m="$1" want="$2" j w h rr x y scale mode position
    j=$(hyprctl monitors -j | jq -r --arg m "$m" '.[] | select(.name==$m)')
    w=$(jq -r '.width'        <<<"$j")
    h=$(jq -r '.height'       <<<"$j")
    rr=$(jq -r '.refreshRate' <<<"$j")
    x=$(jq -r '.x'            <<<"$j")
    y=$(jq -r '.y'            <<<"$j")
    scale=$(jq -r '.scale'    <<<"$j")
    rr=$(LC_NUMERIC=C printf '%.2f' "$rr")  # FR locale = decimal comma, breaks the "W x H@RR" format
    mode="${w}x${h}@${rr}"
    position="${x}x${y}"

    if [[ "$want" == "hdr" ]]; then
        # Both floors forced to literal 0 rather than the EDID-reported 0.041
        # cd/m^2: min_luminance is the floor for native HDR content (games,
        # HDR video), sdr_min_luminance only affects SDR windows composited
        # into the HDR container. The EDID value visibly lifted blacks above
        # what the panel can actually do (confirmed against a bare TTY
        # framebuffer, which has no compositor/CM path to introduce a floor).
        local extra=", sdr_max_luminance = ${SDR_WHITE_LUMINANCE}, sdr_min_luminance = 0, min_luminance = 0"
        hyprctl eval "hl.monitor({ output = \"$m\", mode = \"$mode\", position = \"$position\", scale = ${scale}, bitdepth = 10, cm = \"hdredid\", sdrbrightness = ${SDRBRIGHTNESS}, sdrsaturation = ${SDRSATURATION}${extra} })"
    else
        hyprctl eval "hl.monitor({ output = \"$m\", mode = \"$mode\", position = \"$position\", scale = ${scale}, bitdepth = 8, cm = \"auto\" })"
    fi
}

refresh_bar() { pkill -RTMIN+"$WAYBAR_SIGNAL" waybar 2>/dev/null || true; }

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
    *)      echo "usage: $0 {status|toggle|menu}" >&2; exit 1 ;;
esac
