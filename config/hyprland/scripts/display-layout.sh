#!/usr/bin/env bash
set -euo pipefail

# =========================================================
# display-layout.sh — UI (menu rofi + module waybar) pour la
# disposition d'écrans. Même pattern que set_wallpaper.sh /
# hdr.sh : cette UI ne fait qu'écrire l'état JSON, c'est
# scripts/workspace-manager.sh (le moteur) qui l'applique.
#
#   display-layout.sh menu    -> menu rofi multi-étapes
#   display-layout.sh status  -> JSON pour le module waybar
#
# Résolution des rôles (interne/externe) dupliquée ici en version
# minimale, en lecture seule, juste pour savoir quelles options
# proposer/afficher — la logique d'application reste entièrement
# dans workspace-manager.sh (source de vérité unique).
# =========================================================

STATE_FILE="$HOME/.config/hypr/display-layout.json"
RASI="$HOME/.config/rofi/wallpaper-mode.rasi"
# nf-md-monitor -- GTK/waybar ne supporte pas ::before en CSS (testé,
# "Invalid name of pseudo-class"), donc l'icône du groupe "écran"
# (display+scale+hdr) est injectée ici, en tête du 1er module du trio.
ICON="󰍹"
WAYBAR_SIGNAL=4

resolve_roles() {
    # NB : `[[ cond ]] && var=val` (sans fi) plutôt que `if...fi` est banni
    # dans ce fichier : si c'est la DERNIÈRE commande exécutée d'une fonction
    # et que cond est fausse, le statut de sortie de la fonction devient 1
    # (le `&&` court-circuite) -> avec `set -e`, l'appel de la fonction tue
    # le script entier, silencieusement, dans le cas le plus courant (cond
    # fausse = pas besoin de repli). Bug vécu en prod ici (resolve_roles
    # mourait dès que external_label était déjà non-vide, càd le cas normal)
    # -> toujours `if [[ cond ]]; then var=val; fi` à la place.
    local internal
    mons_json="$(hyprctl monitors all -j)"
    internal="$(jq -r '[.[] | select(.name | test("^(eDP|LVDS|DSI)"))][0].name // empty' <<<"$mons_json")"
    if [[ -z "$internal" ]]; then
        internal="$(jq -r '.[0].name // empty' <<<"$mons_json")"
    fi
    first_external="$(jq -r --arg m "$internal" '[.[] | select(.name != $m)][0].name // empty' <<<"$mons_json")"

    # Noms affichés dans le menu : la dalle interne n'a pas de nom "grand
    # public" exploitable (le descriptif EDID est le fabricant du panneau,
    # ex. "Chimei Innolux ...") -> libellé générique fixe. L'externe, lui,
    # a un vrai nom de marque reconnaissable dans son descriptif EDID -> on
    # en extrait le 1er mot dynamiquement (jamais codé en dur : ça suit
    # l'écran réellement branché, quel qu'il soit).
    internal_label="Laptop"
    external_label="Externe"
    if [[ -n "$first_external" ]]; then
        external_label="$(jq -r --arg m "$first_external" '.[] | select(.name==$m) | .description // empty' <<<"$mons_json" | awk '{print $1}')"
        if [[ -z "$external_label" ]]; then
            external_label="Externe"
        fi
    fi
}

current_state() {
    mode="both"; position="external-left"; align="center"
    if [[ -f "$STATE_FILE" ]]; then
        local v
        v="$(jq -r '.mode // empty'     "$STATE_FILE" 2>/dev/null || true)"
        if [[ "$v" =~ ^(both|internal|external)$ ]]; then mode="$v"; fi
        v="$(jq -r '.position // empty' "$STATE_FILE" 2>/dev/null || true)"
        if [[ "$v" =~ ^(external-left|external-right)$ ]]; then position="$v"; fi
        v="$(jq -r '.align // empty'    "$STATE_FILE" 2>/dev/null || true)"
        if [[ "$v" =~ ^(center|top|bottom)$ ]]; then align="$v"; fi
    fi
}

write_state() {
    python3 -c "
import json
with open('$STATE_FILE', 'w') as f:
    json.dump({'mode': '$1', 'position': '$2', 'align': '$3'}, f)
"
}

refresh_bar() { pkill -RTMIN+"$WAYBAR_SIGNAL" waybar 2>/dev/null || true; }

cmd_menu() {
    resolve_roles
    current_state

    if [[ -z "$first_external" ]]; then
        notify-send "Displays" "No external screen detected — only one screen active."
        exit 0
    fi

    local choice new_mode
    choice=$(printf "All\n%s\n%s" "$internal_label" "$external_label" | rofi -dmenu \
        -theme "$RASI" -theme-str 'listview { columns: 3; }' \
        -mesg "Displays" -name "display-picker" -no-show-icons -no-custom -lines 1)
    [[ -z "$choice" ]] && exit 0
    case "$choice" in
        "All")             new_mode="both" ;;
        "$internal_label") new_mode="internal" ;;
        "$external_label") new_mode="external" ;;
        *)                 exit 0 ;;
    esac

    local new_position="$position" new_align="$align"
    if [[ "$new_mode" == "both" ]]; then
        choice=$(printf "%s à gauche\n%s à droite" "$external_label" "$external_label" | rofi -dmenu \
            -theme "$RASI" \
            -mesg "Position" -name "display-picker" -no-show-icons -no-custom -lines 1)
        [[ -z "$choice" ]] && exit 0
        [[ "$choice" == "$external_label à gauche" ]] && new_position="external-left" || new_position="external-right"

        choice=$(printf "Centré\nHaut\nBas" | rofi -dmenu \
            -theme "$RASI" -theme-str 'listview { columns: 3; }' \
            -mesg "Alignment" -name "display-picker" -no-show-icons -no-custom -lines 1)
        [[ -z "$choice" ]] && exit 0
        case "$choice" in
            "Centré") new_align="center" ;;
            "Haut")   new_align="top" ;;
            "Bas")    new_align="bottom" ;;
        esac
    fi

    write_state "$new_mode" "$new_position" "$new_align"
    bash ~/.config/hypr/scripts/workspace-manager.sh
    refresh_bar
}

cmd_status() {
    resolve_roles
    current_state

    local label tooltip
    case "$mode" in
        internal) label="int" ;;
        external) label="ext" ;;
        *)        label="all" ;;
    esac

    if [[ "$mode" == "both" && -z "$first_external" ]]; then
        tooltip="Internal only (no external detected)\\nClick: change layout"
    elif [[ "$mode" == "both" ]]; then
        tooltip="Both screens · ${position} · ${align}\\nClick: change layout"
    else
        tooltip="${label} · Click: change layout"
    fi

    printf '{"text":"%s %s","class":"display-%s","tooltip":"%s"}\n' "$ICON" "$label" "$mode" "$tooltip"
}

case "${1:-status}" in
    menu)   cmd_menu ;;
    status) cmd_status ;;
    *)      echo "usage: $0 {menu|status}" >&2; exit 1 ;;
esac
