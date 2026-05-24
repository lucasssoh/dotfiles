#!/usr/bin/env bash
WALL_DIR="$HOME/Images/Wallpapers"
CACHE_DIR="$HOME/.cache/filtered_wallpapers"
FILTER_SCRIPT="$HOME/.config/hypr/scripts/wallpaper-filter-one.sh"

mkdir -p "$CACHE_DIR"

# Cache initial
while IFS= read -r -d '' img; do
    bash "$FILTER_SCRIPT" "$img" &
done < <(find -L "$WALL_DIR" -maxdepth 1 -type f \
    \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o -iname "*.webp" \) \
    -print0)

wait

# Watcher temps réel
inotifywait -m -e close_write,moved_to --format '%w%f' "$(readlink -f "$WALL_DIR")" | \
    while read -r filepath; do
        bash "$FILTER_SCRIPT" "$filepath" &
    done
