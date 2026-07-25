#!/bin/bash
# =========================================================
# monitor.sh — rechargement à chaud de Waybar : redémarre le process
# dès que config.jsonc ou style.css est modifié, pour itérer sur le
# thème/la config sans avoir à relancer manuellement. Outil de
# développement, pas lancé par l'autostart de session.
# =========================================================
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
