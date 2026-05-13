#!/usr/bin/env bash

# Configuration des chemins
WALL_DIR="$HOME/Images/Wallpapers"
RASI_THEME="$HOME/.config/rofi/wallpaper.rasi"

# Vérification du daemon awww (spécifique à ton setup Fedora/Hyprland)
if ! pidof awww-daemon >/dev/null; then
    awww-daemon &
    sleep 0.5
fi

# Génération de la liste avec icônes et appel de Rofi
SELECTED=$(
    for img in "$WALL_DIR"/*; do
        # On accepte les extensions courantes (insensible à la casse)
        [[ "$img" =~ \.(jpg|jpeg|png|webp|PNG|JPG)$ ]] || continue
        printf "%s\0icon\x1f%s\n" "$(basename "$img")" "$img"
    done | rofi -dmenu -i -theme "$RASI_THEME" -p "" -name "wallpaper-picker"
)

# Application du wallpaper si un choix a été fait
if [ -n "$SELECTED" ]; then
    awww img "$WALL_DIR/$SELECTED" \
        --transition-type wipe \
        --transition-angle 30 \
        --transition-fps 60 \
        --transition-duration 1
fi
