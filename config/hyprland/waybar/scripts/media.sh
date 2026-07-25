#!/usr/bin/env bash
# =========================================================
# media.sh — module waybar affichant le morceau en cours de lecture
# (titre, artiste, icône par lecteur), via playerctl. Case vide si
# aucun lecteur MPRIS actif ou si la lecture est arrêtée.
# =========================================================

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

# ---- Réglages d'affichage --------------------------------
MAX_TITLE=25
MAX_ARTIST=20
MAX_TOOLTIP=60
SCROLL_WIDTH=30   # largeur visible en mode défilement
SCROLL_ENABLED=0  # 0 = off / 1 = on

# ---- Métadonnées du morceau ------------------------------
TITLE=$(playerctl -p "$PLAYER" metadata title 2>/dev/null | tr '\n' ' ')
ARTIST=$(playerctl -p "$PLAYER" metadata artist 2>/dev/null | tr '\n' ' ')

[[ -z "$TITLE" ]] && TITLE="Unknown"
[[ -z "$ARTIST" ]] && ARTIST=""

# Troncature avec ellipse pour respecter la largeur du module
[[ ${#TITLE}  -gt $MAX_TITLE ]]  && TITLE="${TITLE:0:$((MAX_TITLE-2))}…"
[[ ${#ARTIST} -gt $MAX_ARTIST ]] && ARTIST="${ARTIST:0:$((MAX_ARTIST-2))}…"

# Icône selon le lecteur MPRIS actif
case "$PLAYER" in
    *spotify*) ICON="󰓇" ;;
    *firefox*|*chromium*|*youtube*) ICON="󰗃" ;;
    *mpv*) ICON="󰎁" ;;
    *) ICON="󰎈" ;;
esac

FULL_TEXT="${ICON} ${TITLE}"
[[ -n "$ARTIST" ]] && FULL_TEXT="${FULL_TEXT} · ${ARTIST}"

# Défilement optionnel (désactivé par défaut) : fait glisser une fenêtre
# de SCROLL_WIDTH caractères dans le texte complet, au rythme de l'horloge
if [[ $SCROLL_ENABLED -eq 1 && ${#FULL_TEXT} -gt $SCROLL_WIDTH ]]; then
    LEN=${#FULL_TEXT}
    OFFSET=$(( $(date +%s) % LEN ))
    TEXT="${FULL_TEXT:$OFFSET:$SCROLL_WIDTH}"
else
    TEXT="$FULL_TEXT"
fi

TOOLTIP=$(printf "%s - %s" "$TITLE" "$ARTIST" | head -c $MAX_TOOLTIP)

CLASS="playing"
[[ "$STATUS" == "Paused" ]] && CLASS="paused"

printf '{"text": "%s", "tooltip": "%s", "class": "%s"}' \
    "$TEXT" "$TOOLTIP" "$CLASS"
