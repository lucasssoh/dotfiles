#!/usr/bin/env bash
# =========================================================
# wallpaper-slideshow.sh — infinite wallpaper slideshow loop. Reads the
# playlist (duration, source, image list) written by
# set_wallpaper.sh/Prisme, shuffles the order on every full cycle, and
# applies each image via awww. Launched as a systemd --user service (see
# systemd/wallpaper-slideshow.service), started/stopped by
# restore_wallpaper.sh and slideshow-fullscreen-guard.sh depending on mode
# and fullscreen state.
# =========================================================

# Source folder configurable via ~/.config/prisme/wallpapers.conf -- only
# used as a fallback, see below (the playlist's "source" is enough in the
# vast majority of cases).
WALL_DIR="$HOME/Images/Wallpapers"
WALLPAPERS_CONF="$HOME/.config/prisme/wallpapers.conf"
if [[ -f "$WALLPAPERS_CONF" ]]; then
    configured="$(grep -vE '^[[:space:]]*(#|$)' "$WALLPAPERS_CONF" | head -n1)"
    [[ -n "$configured" ]] && WALL_DIR="${configured/#\~\//$HOME/}"
fi
CACHE_DIR="$HOME/.cache/filtered_wallpapers"
PLAYLIST_FILE="$HOME/.config/hypr/wallpaper-playlist.json"

if ! pidof awww-daemon >/dev/null; then
    awww-daemon &
    sleep 0.5
fi

apply_wall() {
    awww img "$1" \
        --transition-type wipe \
        --transition-angle 30 \
        --transition-fps 60 \
        --transition-duration 1
}

# Fisher-Yates shuffle: avoids replaying the playlist in the same order
shuffle() {
    local arr=("$@")
    local n=${#arr[@]}
    for ((i = n - 1; i > 0; i--)); do
        j=$((RANDOM % (i + 1)))
        tmp="${arr[i]}"
        arr[i]="${arr[j]}"
        arr[j]="$tmp"
    done
    printf '%s\n' "${arr[@]}"
}

# Playlist found: loads duration/source/images from the JSON. Otherwise,
# falls back to every image in WALL_DIR with a default duration.
if [ -f "$PLAYLIST_FILE" ]; then
    DURATION=$(python3 -c "
import json
with open('$PLAYLIST_FILE') as f:
    d = json.load(f)
print(d.get('duration', 120))
")
    SOURCE=$(python3 -c "
import json, os
with open('$PLAYLIST_FILE') as f:
    d = json.load(f)
print(d.get('source', os.path.expanduser('$WALL_DIR')))
")
    mapfile -t walls < <(python3 -c "
import json
with open('$PLAYLIST_FILE') as f:
    d = json.load(f)
for w in d['walls']:
    print(w)
")
else
    DURATION=120
    SOURCE="$WALL_DIR"
    mapfile -t walls < <(find "$WALL_DIR" -maxdepth 1 \
        -iregex '.*\.\(jpg\|jpeg\|png\|webp\|jxl\)' -printf '%f\n')
fi

[ ${#walls[@]} -eq 0 ] && exit 1

# Infinite loop: a freshly shuffled order per full playlist cycle
while true; do
    mapfile -t shuffled < <(shuffle "${walls[@]}")
    for img in "${shuffled[@]}"; do
        apply_wall "$SOURCE/$img"
        sleep "$DURATION"
    done
done
