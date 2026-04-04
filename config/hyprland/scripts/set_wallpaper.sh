#!/usr/bin/env bash

WALLPAPER_DIR="$HOME/Images/Wallpapers"
STATE_FILE="$HOME/.cache/current_wallpaper"

# Crée le dossier cache si nécessaire
mkdir -p "$(dirname "$STATE_FILE")"

# Crée le fichier d'état vide s'il n'existe pas
[ ! -f "$STATE_FILE" ] && touch "$STATE_FILE"

# Démarre swww si pas déjà lancé
pgrep -x swww-daemon >/dev/null || swww init

while true; do
    # Liste les wallpapers récents, sélection via rofi
    SELECTED=$(ls -t "$WALLPAPER_DIR" | rofi -dmenu -p "Wallpaper")
    [ -z "$SELECTED" ] && exit 0

    FULL_PATH="$WALLPAPER_DIR/$SELECTED"

    # Applique le wallpaper avec transition
    swww img "$FULL_PATH" \
        --transition-type fade \
        --transition-duration 0.2

    # 🔥 Sauvegarde du dernier wallpaper
    echo "$FULL_PATH" > "$STATE_FILE"
done
