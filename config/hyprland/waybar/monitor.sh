#!/bin/bash
exec > /tmp/waybar_monitor.log 2>&1

CONFIG_FILES=(
    "$HOME/.config/waybar/config.jsonc"
    "$HOME/.config/waybar/style.css"
)

while true; do
    pkill -x waybar; sleep 0.5; waybar &
    inotifywait -e close_write -e moved_to "${CONFIG_FILES[@]}" 2>/dev/null
    echo "[$(date '+%H:%M:%S')] Changement détecté, rechargement..."
done
