#!/usr/bin/env bash

WALL_DIR="$HOME/Images/Wallpapers"
CONF_FILE="$HOME/.config/hypr/hyprpaper.conf"

# Sélection
SELECTED=$(ls -t "$WALL_DIR" | grep -E "\.(jpg|jpeg|png|webp|jxl)$" | rofi -dmenu -p "Wallpaper")
[ -z "$SELECTED" ] && exit 0

FULL_PATH="$WALL_DIR/$SELECTED"

# Mise à jour en temps réel
hyprctl hyprpaper unload all
hyprctl hyprpaper preload "$FULL_PATH"
hyprctl hyprpaper wallpaper ",$FULL_PATH"

# Persistance pour le prochain boot (écriture du config)
cat <<EOF > "$CONF_FILE"
preload = $FULL_PATH
wallpaper = ,$FULL_PATH
splash = false
EOF
