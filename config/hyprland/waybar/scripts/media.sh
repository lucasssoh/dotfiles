#!/usr/bin/env bash
# =========================================================
# media.sh — waybar module showing the currently playing track (title,
# artist, per-player icon), via playerctl. Empty widget if no MPRIS
# player is active or playback is stopped.
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

# ---- Display settings --------------------------------
MAX_TITLE=25
MAX_ARTIST=20
MAX_TOOLTIP=60
SCROLL_WIDTH=30   # visible width in scroll mode
SCROLL_ENABLED=0  # 0 = off / 1 = on

# ---- Track metadata ------------------------------
TITLE=$(playerctl -p "$PLAYER" metadata title 2>/dev/null | tr '\n' ' ')
ARTIST=$(playerctl -p "$PLAYER" metadata artist 2>/dev/null | tr '\n' ' ')

[[ -z "$TITLE" ]] && TITLE="Unknown"
[[ -z "$ARTIST" ]] && ARTIST=""

# Truncate with an ellipsis to respect the module's width
[[ ${#TITLE}  -gt $MAX_TITLE ]]  && TITLE="${TITLE:0:$((MAX_TITLE-2))}…"
[[ ${#ARTIST} -gt $MAX_ARTIST ]] && ARTIST="${ARTIST:0:$((MAX_ARTIST-2))}…"

# Icon based on the active MPRIS player
case "$PLAYER" in
    *spotify*) ICON="󰓇" ;;
    *firefox*|*chromium*|*youtube*) ICON="󰗃" ;;
    *mpv*) ICON="󰎁" ;;
    *) ICON="󰎈" ;;
esac

FULL_TEXT="${ICON} ${TITLE}"
[[ -n "$ARTIST" ]] && FULL_TEXT="${FULL_TEXT} · ${ARTIST}"

# Optional scrolling (disabled by default): slides a SCROLL_WIDTH-char
# window across the full text, paced by the clock
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
