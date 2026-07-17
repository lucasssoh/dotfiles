#!/usr/bin/env bash
set -euo pipefail

# =========================================================
# scale.sh — bascule le scale (mise à l'échelle) par écran pour
# Hyprland + Waybar, même pattern "par écran" que hdr.sh : chaque
# instance de Waybar affiche SON écran, le clic cible l'écran SOUS
# LE CURSEUR (barre cliquée) — WAYBAR_OUTPUT_NAME n'est pas fiable
# dans les gestionnaires de clic.
#
#   scale.sh status  -> JSON pour le module waybar (écran DE CETTE barre)
#   scale.sh menu    -> menu rofi des scales "propres" pour l'écran cliqué
#
# Les valeurs proposées ne sont JAMAIS une liste fixe codée en dur : elles
# sont recalculées par écran, à partir de sa résolution native, en ne
# gardant que les paliers de la grille standard (quarts, 100%..300%, comme
# GNOME) qui donnent une résolution LOGIQUE ENTIÈRE en largeur ET en
# hauteur pour CETTE résolution précise — donc jamais de valeur "moche"
# (floue/sous-pixel). Ça correspond à ce qu'Hyprland impose déjà de facto :
# une demande scale=1.2 sur l'externe (2560×1440, testé en session) a été
# silencieusement arrondie à 1.25, seul palier propre proche pour cette
# largeur (2560/1.25=2048, entier ; 2560/1.2=2133.33, pas entier).
#
# N'applique rien directement : écrit le scale choisi par RÔLE (jamais par
# nom de connecteur, cf. scripts/workspace-manager.sh) dans l'état
# persistant, puis rappelle ce moteur unique — même pattern que
# scripts/display-layout.sh (état + moteur, pas de logique dupliquée).
# =========================================================

STATE_FILE="$HOME/.config/hypr/scale.json"
RASI="$HOME/.config/rofi/theme.rasi"
WAYBAR_SIGNAL=5

# Grille standard de paliers "propres" (quarts, 100% à 300%) + leur écriture
# décimale exacte -- jamais générée via printf/awk (aucun risque de bug de
# locale décimale, cf. session : LC_NUMERIC=fr_FR casse `printf '%.2f'`).
PCTS=(100 125 150 175 200 225 250 275 300)
declare -A PCT_DECIMAL=(
    [100]="1" [125]="1.25" [150]="1.5" [175]="1.75" [200]="2"
    [225]="2.25" [250]="2.5" [275]="2.75" [300]="3"
)

focused() {
    hyprctl monitors -j | jq -r '.[] | select(.focused==true) | .name'
}

# Écran situé sous le curseur (= barre que l'on vient de cliquer)
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

# Rôle par nom d'écran -- jamais l'inverse (même détection que
# scripts/workspace-manager.sh : interne = eDP*/LVDS*/DSI*).
role_of() {
    local m="$1"
    if [[ "$m" =~ ^(eDP|LVDS|DSI) ]]; then echo "internal"; else echo "external"; fi
}

# Paliers propres (résolution logique entière en W et H) pour un écran donné.
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
