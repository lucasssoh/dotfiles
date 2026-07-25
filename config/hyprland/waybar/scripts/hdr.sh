#!/usr/bin/env bash
set -euo pipefail

# =========================================================
# hdr.sh — bascule SDR/HDR par écran pour Hyprland + Waybar
#
#   hdr.sh status   -> JSON pour le module waybar (écran DE CETTE barre)
#   hdr.sh toggle    -> bascule l'écran sous le curseur (barre cliquée)
#   hdr.sh menu      -> menu rofi (écrans compatibles HDR uniquement)
#
# En mode "par écran", chaque instance de Waybar affiche et contrôle
# SON propre écran (via WAYBAR_OUTPUT_NAME côté affichage, et la position
# du curseur côté clic — WAYBAR_OUTPUT_NAME n'est pas fiable dans les
# gestionnaires de clic).
# =========================================================

# ---- Réglages ------------------------------------------------
SDRBRIGHTNESS="1.2"     # luminosité du contenu SDR quand l'écran est en HDR (1.0..2.0)
SDRSATURATION="1.0"     # saturation du contenu SDR en HDR
WAYBAR_SIGNAL=3         # doit correspondre à "signal" dans config.jsonc
RASI="$HOME/.config/rofi/theme.rasi"   # thème du menu (adapte si besoin)
ICON=""               # glyphe écran (nf-md-monitor)

CACHE_DIR="${XDG_RUNTIME_DIR:-/tmp}/hdr-toggle"

# ---- Helpers -------------------------------------------------

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

# Vrai si l'écran est actuellement en HDR (pipeline 10-bit actif)
is_hdr() {
    local m="$1" fmt
    fmt=$(hyprctl monitors -j | jq -r --arg m "$m" \
        '.[] | select(.name==$m) | .currentFormat')
    [[ "$fmt" == *2101010* ]]
}

# Support HDR déclaré dans l'EDID — mis en cache (l'EDID ne change pas).
# edid-decode absent / EDID introuvable -> on considère compatible (on ne bloque pas).
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

# Luminance HDR réelle du panneau, lue dans l'EDID (Desired content max
# frame-average / min luminance) -- sans ça, Hyprland retombe sur des défauts
# génériques (sdr_max_luminance=80, sdr_min_luminance=0.2) qui n'ont aucun
# rapport avec la vraie capacité de l'écran -> HDR plat/délavé. Mis en cache
# comme hdr_capable (l'EDID ne change pas). Imprime "max min", vide si
# indisponible -- apply() retombe alors sur cm="hdr" (comportement actuel).
hdr_luminance() {
    local m="$1" cache="$CACHE_DIR/lum-$m" edid="" path max="" min=""
    if [[ -f "$cache" ]]; then
        cat "$cache"
        return
    fi
    mkdir -p "$CACHE_DIR"
    for path in /sys/class/drm/*-"$m"/edid; do
        [[ -e "$path" ]] && { edid="$path"; break; }
    done
    if [[ -n "$edid" ]] && command -v edid-decode >/dev/null 2>&1; then
        max=$(edid-decode "$edid" 2>/dev/null \
            | sed -n 's/.*Desired content max frame-average luminance:.*(\([0-9.]*\) cd\/m\^2).*/\1/p' | head -n1)
        min=$(edid-decode "$edid" 2>/dev/null \
            | sed -n 's/.*Desired content min luminance:.*(\([0-9.]*\) cd\/m\^2).*/\1/p' | head -n1)
        # sdr_max_luminance exige un entier côté Hyprland : un float est
        # rejeté avec "integer type requires a bool or an integer".
        if [[ -n "$max" ]]; then
            max="${max%%.*}"
        fi
    fi
    printf '%s %s' "$max" "$min" > "$cache"
    printf '%s %s' "$max" "$min"
}

# Applique HDR ou SDR en préservant mode/position/scale courants
#
# NB : ce setup charge sa config via un binding Lua custom (hl.*), qui bascule
# Hyprland sur un parser "non-legacy" où `hyprctl keyword` est refusé
# ("keyword can't work with non-legacy parsers. Use eval."). On pilote donc
# via `hyprctl eval '<lua hl.*>'` (même pattern que scripts/workspace-manager.sh).
apply() {
    local m="$1" want="$2" j w h rr x y scale mode position
    j=$(hyprctl monitors -j | jq -r --arg m "$m" '.[] | select(.name==$m)')
    w=$(jq -r '.width'        <<<"$j")
    h=$(jq -r '.height'       <<<"$j")
    rr=$(jq -r '.refreshRate' <<<"$j")
    x=$(jq -r '.x'            <<<"$j")
    y=$(jq -r '.y'            <<<"$j")
    scale=$(jq -r '.scale'    <<<"$j")
    rr=$(LC_NUMERIC=C printf '%.2f' "$rr")  # locale FR = virgule décimale, casse le format "W x H@RR"
    mode="${w}x${h}@${rr}"
    position="${x}x${y}"

    if [[ "$want" == "hdr" ]]; then
        local lum max min cm="hdr" extra=""
        lum="$(hdr_luminance "$m")"
        max="${lum%% *}"; min="${lum##* }"
        if [[ -n "$max" && -n "$min" ]]; then
            cm="hdredid"
            extra=", sdr_max_luminance = ${max}, sdr_min_luminance = ${min}"
        fi
        hyprctl eval "hl.monitor({ output = \"$m\", mode = \"$mode\", position = \"$position\", scale = ${scale}, bitdepth = 10, cm = \"${cm}\", sdrbrightness = ${SDRBRIGHTNESS}, sdrsaturation = ${SDRSATURATION}${extra} })"
    else
        hyprctl eval "hl.monitor({ output = \"$m\", mode = \"$mode\", position = \"$position\", scale = ${scale}, bitdepth = 8, cm = \"auto\" })"
    fi
}

refresh_bar() { pkill -RTMIN+"$WAYBAR_SIGNAL" waybar 2>/dev/null || true; }

# ---- Sous-commandes ------------------------------------------

cmd_status() {
    # L'écran de CETTE barre ; repli sur le focus si lancé à la main
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
    # L'écran sous le curseur = la barre cliquée ; repli sur le focus
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
