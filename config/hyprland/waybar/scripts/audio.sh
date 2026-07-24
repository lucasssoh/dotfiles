#!/usr/bin/env bash
set -euo pipefail

# pactl traduit ses labels selon la locale (ex: "Nom"/"Description" en
# français) -- on force le C pour un parsing stable, indépendant de la
# langue système.
export LC_ALL=C

# =========================================================
# audio.sh — sélecteur de périphérique audio (remplace wiremix)
#
#   audio.sh output   -> choisir le périphérique de sortie par défaut
#   audio.sh input     -> choisir le périphérique d'entrée par défaut
#
# Backend pactl (pipewire-pulse). Le volume/mute restent gérés
# ailleurs (wpctl via les raccourcis clavier et le clic sur le module) ;
# ce script ne fait QUE le choix du périphérique par défaut.
# =========================================================

RASI="$HOME/.config/rofi/theme.rasi"
KIND="${1:-output}"

case "$KIND" in
    output)
        PACTL_KIND="sinks"
        DEFAULT_CMD="get-default-sink"
        SET_CMD="set-default-sink"
        TITLE="Sortie audio"
        ;;
    input)
        PACTL_KIND="sources"
        DEFAULT_CMD="get-default-source"
        SET_CMD="set-default-source"
        TITLE="Entrée audio"
        ;;
    *)
        echo "usage: $0 {output|input}" >&2
        exit 1
        ;;
esac

icon_for() {
    local desc="$1"
    case "$desc" in
        *[Hh]eadset*|*[Hh]eadphone*|*[Ee]arbuds*) printf '󰋋' ;;
        *HDMI*|*DisplayPort*)                     printf '󰡁' ;;
        *[Mm]icrophone*|*[Mm]ic*)                  printf '󰍬' ;;
        *)                                          printf '󰓃' ;;
    esac
}

declare -A NAME_OF
ROWS=()

# Appelée directement (pas en $(...)) : cf. wifi.sh pour la raison.
build_rows() {
    ROWS=()
    NAME_OF=()

    local default name desc mark row
    default=$(pactl "$DEFAULT_CMD")

    while IFS= read -r name; do
        [[ -z "$name" ]] && continue
        # Les sources ".monitor" sont le retour de chaque sortie audio, pas
        # de vrais micros -- sans ce filtre elles polluent le choix d'entrée.
        [[ "$KIND" == "input" && "$name" == *.monitor ]] && continue
        desc=$(pactl list "$PACTL_KIND" \
            | awk -v n="$name" '
                $1=="Name:" && $2==n {f=1}
                f && /Description:/ {sub(/^[ \t]*Description: /,""); print; exit}
              ')
        [[ -z "$desc" ]] && desc="$name"

        mark="  "
        [[ "$name" == "$default" ]] && mark=" "

        row="${mark}$(icon_for "$desc")  ${desc}"
        ROWS+=("$row")
        NAME_OF["$row"]="$name"
    done < <(pactl list short "$PACTL_KIND" | awk -F'\t' '{print $2}')
}

build_rows

if [[ ${#ROWS[@]} -eq 0 ]]; then
    notify-send "$TITLE" "Aucun périphérique détecté"
    exit 0
fi

choice=$(printf '%s\n' "${ROWS[@]}" \
    | rofi -dmenu -theme "$RASI" -mesg "$TITLE" -no-custom -format s -i)

[[ -z "$choice" ]] && exit 0

name="${NAME_OF[$choice]:-}"
if [[ -n "$name" ]]; then
    if pactl "$SET_CMD" "$name" >/dev/null 2>&1; then
        notify-send "$TITLE" "Périphérique par défaut changé"
    else
        notify-send "$TITLE" "Échec du changement de périphérique"
    fi
fi
