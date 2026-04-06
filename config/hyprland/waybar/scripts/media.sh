#!/usr/bin/env bash
# media.sh — lecteur media flottant pour Waybar (custom/media)
# Dépendances: playerctl
# Retourne du JSON pour waybar return-type: json

PLAYER=$(playerctl -l 2>/dev/null | head -1)

if [[ -z "$PLAYER" ]]; then
    echo '{"text": "", "tooltip": "", "class": "none"}'
    exit 0
fi

STATUS=$(playerctl -p "$PLAYER" status 2>/dev/null)
if [[ "$STATUS" == "Stopped" || -z "$STATUS" ]]; then
    echo '{"text": "", "tooltip": "", "class": "stopped"}'
    exit 0
fi

TITLE=$(playerctl -p "$PLAYER" metadata title 2>/dev/null | head -c 30)
ARTIST=$(playerctl -p "$PLAYER" metadata artist 2>/dev/null | head -c 24)

# Tronquer proprement
[[ ${#TITLE}  -ge 30 ]] && TITLE="${TITLE:0:28}…"
[[ ${#ARTIST} -ge 24 ]] && ARTIST="${ARTIST:0:22}…"

# Icône selon le player
case "$PLAYER" in
    *spotify*) ICON="󰓇" ;;
    *firefox*|*chromium*|*youtube*) ICON="󰗃" ;;
    *mpv*)     ICON="󰎁" ;;
    *)         ICON="󰎈" ;;
esac

# Icône play/pause
if [[ "$STATUS" == "Playing" ]]; then
    PLAY_ICON="⏸"
else
    PLAY_ICON="▶"
fi

TEXT="${ICON} ${TITLE}"
[[ -n "$ARTIST" ]] && TEXT="${TEXT} · ${ARTIST}"
TOOLTIP="${TITLE}\n${ARTIST}\n\nClic: play/pause\nClic droit: suivant\nClic milieu: précédent"

CLASS="playing"
[[ "$STATUS" == "Paused" ]] && CLASS="paused"

printf '{"text": "%s", "tooltip": "%s", "class": "%s"}' \
    "$TEXT" "$TOOLTIP" "$CLASS"
