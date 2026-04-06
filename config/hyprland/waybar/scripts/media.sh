#!/usr/bin/env bash
# media.sh — version clean, robuste, contrôlée

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

# =========================
# CONFIG
# =========================
MAX_TITLE=25
MAX_ARTIST=20
MAX_TOOLTIP=60
SCROLL_WIDTH=30   # largeur visible
SCROLL_ENABLED=0  # 0 = off / 1 = on

# =========================
# DATA
# =========================
TITLE=$(playerctl -p "$PLAYER" metadata title 2>/dev/null | tr '\n' ' ')
ARTIST=$(playerctl -p "$PLAYER" metadata artist 2>/dev/null | tr '\n' ' ')

# fallback safe
[[ -z "$TITLE" ]] && TITLE="Unknown"
[[ -z "$ARTIST" ]] && ARTIST=""

# =========================
# TRUNCATION PROPRE
# =========================
[[ ${#TITLE}  -gt $MAX_TITLE ]]  && TITLE="${TITLE:0:$((MAX_TITLE-2))}…"
[[ ${#ARTIST} -gt $MAX_ARTIST ]] && ARTIST="${ARTIST:0:$((MAX_ARTIST-2))}…"

# =========================
# ICON
# =========================
case "$PLAYER" in
    *spotify*) ICON="󰓇" ;;
    *firefox*|*chromium*|*youtube*) ICON="󰗃" ;;
    *mpv*) ICON="󰎁" ;;
    *) ICON="󰎈" ;;
esac

# =========================
# TEXT BUILD
# =========================
FULL_TEXT="${ICON} ${TITLE}"
[[ -n "$ARTIST" ]] && FULL_TEXT="${FULL_TEXT} · ${ARTIST}"

# =========================
# SCROLL (optionnel)
# =========================
if [[ $SCROLL_ENABLED -eq 1 && ${#FULL_TEXT} -gt $SCROLL_WIDTH ]]; then
    LEN=${#FULL_TEXT}
    OFFSET=$(( $(date +%s) % LEN ))
    TEXT="${FULL_TEXT:$OFFSET:$SCROLL_WIDTH}"
else
    TEXT="$FULL_TEXT"
fi

# =========================
# TOOLTIP SAFE
# =========================
TOOLTIP=$(printf "%s - %s" "$TITLE" "$ARTIST" | head -c $MAX_TOOLTIP)

# =========================
# CLASS
# =========================
CLASS="playing"
[[ "$STATUS" == "Paused" ]] && CLASS="paused"

# =========================
# OUTPUT
# =========================
printf '{"text": "%s", "tooltip": "%s", "class": "%s"}' \
    "$TEXT" "$TOOLTIP" "$CLASS"
