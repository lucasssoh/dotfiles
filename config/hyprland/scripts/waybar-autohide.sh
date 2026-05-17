#!/usr/bin/env bash
DELAY=0.5
HIDE_DELAY=10  # cycles avant de cacher (~5s)
TOGGLE_SCRIPT="$HOME/.config/hypr/scripts/waybar-toggle.sh"

rm -f /tmp/waybar-hidden /tmp/waybar-locked

if pkill waybar; then
    sleep 0.5
fi
waybar > /dev/null 2>&1 &
sleep 0.5

hide_counter=0

while true; do
    sleep "$DELAY"
    POS=$(hyprctl cursorpos 2>/dev/null)
    Y=$(echo "$POS" | grep -oP '(?<=, )\d+')
    [ -z "$Y" ] && continue

    if [ "$Y" -le 30 ]; then
        hide_counter=0
        "$TOGGLE_SCRIPT" show
    else
        hide_counter=$((hide_counter + 1))
        if [ "$hide_counter" -ge "$HIDE_DELAY" ]; then
            "$TOGGLE_SCRIPT" hide
            hide_counter=0
        fi
    fi
done
