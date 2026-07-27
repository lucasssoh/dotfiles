#!/usr/bin/env bash
set -euo pipefail

# pactl translates its labels according to locale (e.g. "Name"/"Description"
# in French) -- forcing C locale here for stable parsing, independent of
# the system language.
export LC_ALL=C

# =========================================================
# audio.sh — audio device picker (replaces wiremix)
#
#   audio.sh output   -> choose the default output device
#   audio.sh input     -> choose the default input device
#
# pactl backend (pipewire-pulse). Volume/mute stay handled elsewhere
# (wpctl via keyboard shortcuts and clicking the module); this script
# ONLY picks the default device.
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

declare -A NAME_OF  # row shown in rofi -> pactl device name
ROWS=()

# Fills ROWS/NAME_OF as global variables instead of returning a result via
# $(...): see wifi.sh for why (a subshell would lose the associative
# arrays populated inside it).
build_rows() {
    ROWS=()
    NAME_OF=()

    local default name desc mark row
    default=$(pactl "$DEFAULT_CMD")

    while IFS= read -r name; do
        [[ -z "$name" ]] && continue
        # ".monitor" sources are the loopback of each audio output, not real
        # mics -- without this filter they'd clutter the input picker.
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
