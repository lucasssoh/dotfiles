#!/usr/bin/env bash

WALL_DIR="$HOME/Images/Wallpapers"
PLAYLIST_FILE="$HOME/.config/hypr/wallpaper-playlist.json"

if ! pidof awww-daemon >/dev/null; then
    awww-daemon &
    sleep 0.5
fi

if [ ! -f "$PLAYLIST_FILE" ]; then
    exit 0
fi

MODE=$(python3 -c "import json; print(json.load(open('$PLAYLIST_FILE'))['mode'])")

if [ "$MODE" = "static" ]; then
    # Mode Statique : On s'assure que systemd n'exécute pas le slideshow
    systemctl --user stop wallpaper-slideshow.service 2>/dev/null
    
    SELECTED_WALL=$(python3 -c "import json; print(json.load(open('$PLAYLIST_FILE'))['walls'][0])")
    # `source` est écrit par Prisme (Original vs Filtré) -- absent des
    # playlists écrites par l'ancien picker rofi, d'où le repli sur WALL_DIR.
    SRC_DIR=$(python3 -c "import json; d = json.load(open('$PLAYLIST_FILE')); print(d.get('source') or '$WALL_DIR')")
    awww img "$SRC_DIR/$SELECTED_WALL" --transition-type none

elif [ "$MODE" = "dynamic" ]; then
    # Mode Dynamique : On demande poliment à systemd de lancer TON service personnalisé
    systemctl --user start wallpaper-slideshow.service
fi
