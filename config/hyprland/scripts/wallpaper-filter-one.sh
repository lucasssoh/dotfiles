#!/usr/bin/env bash
CACHE_DIR="$HOME/.cache/filtered_wallpapers"
img="$1"
filename=$(basename "$img")
cached="$CACHE_DIR/$filename"

[[ "$img" =~ \.(jpg|jpeg|png|webp|PNG|JPG)$ ]] || exit 0
[ ! -f "$cached" ] || [ "$img" -nt "$cached" ] || exit 0

magick "$img" -modulate 100,10 -attenuate 0.8 +noise Gaussian "$cached" && \
    notify-send "Wallpaper prêt" "$filename filtré" --expire-time=2000
