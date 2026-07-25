#!/usr/bin/env bash
# =========================================================
# restore_wallpaper.sh — réapplique le fond d'écran au démarrage de la
# session, à partir de l'état persisté par Prisme/set_wallpaper.sh dans
# wallpaper-playlist.json. Lancé par l'autostart Hyprland (hyprland.lua).
# =========================================================

# Dossier source configurable via ~/.config/prisme/wallpapers.conf --
# n'intervient qu'en repli, cf. plus bas (le "source" de la playlist
# suffit dans l'immense majorité des cas).
WALL_DIR="$HOME/Images/Wallpapers"
WALLPAPERS_CONF="$HOME/.config/prisme/wallpapers.conf"
if [[ -f "$WALLPAPERS_CONF" ]]; then
    configured="$(grep -vE '^[[:space:]]*(#|$)' "$WALLPAPERS_CONF" | head -n1)"
    [[ -n "$configured" ]] && WALL_DIR="${configured/#\~\//$HOME/}"
fi
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
    # Mode statique : s'assurer que le service de diaporama n'est pas actif
    systemctl --user stop wallpaper-slideshow.service 2>/dev/null

    SELECTED_WALL=$(python3 -c "import json; print(json.load(open('$PLAYLIST_FILE'))['walls'][0])")
    # `source` est écrit par Prisme (Original vs Filtré) -- absent des
    # playlists écrites par l'ancien picker rofi, d'où le repli sur WALL_DIR.
    SRC_DIR=$(python3 -c "import json; d = json.load(open('$PLAYLIST_FILE')); print(d.get('source') or '$WALL_DIR')")
    awww img "$SRC_DIR/$SELECTED_WALL" --transition-type none

elif [ "$MODE" = "dynamic" ]; then
    # Mode dynamique : délègue au service systemd dédié (diaporama)
    systemctl --user start wallpaper-slideshow.service
fi
