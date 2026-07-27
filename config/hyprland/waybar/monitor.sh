#!/bin/bash
# =========================================================
# monitor.sh — hot-reload for Waybar: restarts the process as soon as
# config.jsonc or style.css changes, to iterate on the theme/config
# without manually relaunching. Development tool, not started by the
# session autostart.
# =========================================================
exec > /tmp/waybar_monitor.log 2>&1

CONFIG_FILES=(
    "$HOME/.config/waybar/config.jsonc"
    "$HOME/.config/waybar/style.css"
)

while true; do
    pkill -x waybar; sleep 0.5; waybar &
    inotifywait -e close_write -e moved_to "${CONFIG_FILES[@]}" 2>/dev/null
    echo "[$(date '+%H:%M:%S')] Change detected, reloading..."
done
