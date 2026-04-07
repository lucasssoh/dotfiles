#!/usr/bin/env bash

WALLPAPER_DIR="$HOME/Images/Wallpapers"
STATE_FILE="$HOME/.cache/current_wallpaper"

# On filtre uniquement les formats d'image (dont jxl)
SELECTED=$(ls -t "$WALLPAPER_DIR" | grep -E "\.(jpg|jpeg|png|webp|jxl)$" | rofi -dmenu -p "Wallpaper")

[ -z "$SELECTED" ] && exit 0

FULL_PATH="$WALLPAPER_DIR/$SELECTED"

# On vérifie si le daemon tourne, sinon on le lance en arrière-plan
if ! pgrep -x "swww-daemon" > /dev/null; then
    swww-daemon &
    sleep 0.5 # Petit délai pour laisser le temps au socket de s'ouvrir
fi

swww img "$FULL_PATH" \
    --transition-type fade \
    --transition-duration 0.2 \
    --transition-fps 75 # Optionnel : caler sur ton taux de rafraîchissement

echo "$FULL_PATH" > "$STATE_FILE"
