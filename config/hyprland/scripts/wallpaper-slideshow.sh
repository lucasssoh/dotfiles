#!/usr/bin/env bash
WALL_DIR="$HOME/Images/Wallpapers"
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

if [ -f "$PLAYLIST_FILE" ]; then
    DURATION=$(python3 -c "
import json
with open('$PLAYLIST_FILE') as f:
    d = json.load(f)
print(d.get('duration', 120))
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
    mapfile -t walls < <(find "$WALL_DIR" -maxdepth 1 \
        -iregex '.*\.\(jpg\|jpeg\|png\|webp\)' -printf '%f\n')
fi

[ ${#walls[@]} -eq 0 ] && exit 1

while true; do
    mapfile -t shuffled < <(shuffle "${walls[@]}")
    for img in "${shuffled[@]}"; do
        apply_wall "$WALL_DIR/$img"
        sleep "$DURATION"
    done
done
