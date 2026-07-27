#!/usr/bin/env bash
set -euo pipefail

# =========================================================
# scale.sh — toggles per-screen scaling for Hyprland + Waybar, same
# "per-screen" pattern as hdr.sh: each Waybar instance shows ITS screen,
# a click targets the screen UNDER THE CURSOR (the bar that was
# clicked) — WAYBAR_OUTPUT_NAME isn't reliable in click handlers.
#
#   scale.sh status  -> JSON for the waybar module (THIS bar's screen)
#   scale.sh menu    -> rofi menu of "clean" scales for the clicked screen
#
# The offered values are NEVER a fixed hardcoded list: they're recomputed
# per screen, from its native resolution, keeping only the steps of the
# standard grid (quarters, 100%..300%, like GNOME) that yield a WHOLE
# logical resolution in both width AND height for THAT exact resolution
# — so never an "ugly" value (blurry/sub-pixel). This matches what
# Hyprland already enforces de facto: on a 2560x1440 screen, a
# scale=1.2 request gets silently rounded to 1.25, the only nearby clean
# step for this width (2560/1.25=2048, whole; 2560/1.2=2133.33, not
# whole).
#
# Applies nothing directly: writes the chosen scale by ROLE (never by
# connector name, see scripts/workspace-manager.sh) to the persistent
# state, then calls back into that single engine — same pattern as
# scripts/display-layout.sh (state + engine, no duplicated logic).
# =========================================================

STATE_FILE="$HOME/.config/hypr/scale.json"
RASI="$HOME/.config/rofi/theme.rasi"
WAYBAR_SIGNAL=5

# Standard grid of "clean" steps (quarters, 100% to 300%) + their exact
# decimal spelling -- never generated via printf/awk (no risk of a decimal
# locale bug, see: LC_NUMERIC=fr_FR breaks `printf '%.2f'`).
PCTS=(100 125 150 175 200 225 250 275 300)
declare -A PCT_DECIMAL=(
    [100]="1" [125]="1.25" [150]="1.5" [175]="1.75" [200]="2"
    [225]="2.25" [250]="2.5" [275]="2.75" [300]="3"
)

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

# Role from screen name -- never the reverse (same detection as
# scripts/workspace-manager.sh: internal = eDP*/LVDS*/DSI*).
role_of() {
    local m="$1"
    if [[ "$m" =~ ^(eDP|LVDS|DSI) ]]; then echo "internal"; else echo "external"; fi
}

# Clean steps (whole logical resolution in W and H) for a given screen.
clean_pcts_for() {
    local m="$1" w h pct
    w=$(hyprctl monitors -j | jq -r --arg m "$m" '.[] | select(.name==$m) | .width')
    h=$(hyprctl monitors -j | jq -r --arg m "$m" '.[] | select(.name==$m) | .height')
    for pct in "${PCTS[@]}"; do
        if (( (w * 100) % pct == 0 && (h * 100) % pct == 0 )); then
            echo "$pct"
        fi
    done
}

refresh_bar() { pkill -RTMIN+"$WAYBAR_SIGNAL" waybar 2>/dev/null || true; }

write_scale_state() {
    local role="$1" decimal="$2" int_val="1" ext_val="1.25" v
    if [[ -f "$STATE_FILE" ]]; then
        v="$(jq -r '.internal // empty' "$STATE_FILE" 2>/dev/null || true)"
        if [[ -n "$v" ]]; then int_val="$v"; fi
        v="$(jq -r '.external // empty' "$STATE_FILE" 2>/dev/null || true)"
        if [[ -n "$v" ]]; then ext_val="$v"; fi
    fi
    if [[ "$role" == "internal" ]]; then int_val="$decimal"; else ext_val="$decimal"; fi
    python3 -c "
import json
with open('$STATE_FILE', 'w') as f:
    json.dump({'internal': '$int_val', 'external': '$ext_val'}, f)
"
}

cmd_status() {
    local m="${WAYBAR_OUTPUT_NAME:-$(focused)}"
    if [[ -z "$m" ]]; then
        printf '{"text":"","class":"scale-na","tooltip":"No display"}\n'
        return
    fi
    local scale_val pct
    scale_val=$(hyprctl monitors -j | jq -r --arg m "$m" '.[] | select(.name==$m) | .scale')
    pct=$(jq -n --argjson s "$scale_val" '($s * 100) | round')
    printf '{"text":"%s%%","class":"scale","tooltip":"%s · %s%%\\nClick: change scale"}\n' "$pct" "$m" "$pct"
}

cmd_menu() {
    local m; m=$(monitor_at_cursor) || true
    [[ -z "$m" ]] && m=$(focused)
    [[ -z "$m" ]] && exit 0

    local role; role=$(role_of "$m")
    local current_scale current_pct
    current_scale=$(hyprctl monitors -j | jq -r --arg m "$m" '.[] | select(.name==$m) | .scale')
    current_pct=$(jq -n --argjson s "$current_scale" '($s * 100) | round')

    local rows=() pct state
    while read -r pct; do
        [[ -z "$pct" ]] && continue
        if [[ "$pct" == "$current_pct" ]]; then state="●"; else state="○"; fi
        rows+=("$state  ${pct}%")
    done < <(clean_pcts_for "$m")

    if [[ ${#rows[@]} -eq 0 ]]; then
        notify-send "Scale" "No clean scale step found for $m"
        exit 0
    fi

    local choice chosen_pct decimal
    choice=$(printf '%s\n' "${rows[@]}" \
        | rofi -dmenu -theme "$RASI" -p "Scale · $m" -no-custom -format s -i)
    [[ -z "$choice" ]] && exit 0

    chosen_pct=$(grep -oE '[0-9]+' <<<"$choice")
    decimal="${PCT_DECIMAL[$chosen_pct]:-}"
    [[ -z "$decimal" ]] && exit 0

    write_scale_state "$role" "$decimal"
    bash ~/.config/hypr/scripts/workspace-manager.sh
    refresh_bar
}

case "${1:-status}" in
    status) cmd_status ;;
    menu)   cmd_menu ;;
    *)      echo "usage: $0 {status|menu}" >&2; exit 1 ;;
esac
