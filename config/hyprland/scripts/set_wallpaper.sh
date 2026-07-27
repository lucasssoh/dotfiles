#!/usr/bin/env bash
# =========================================================
# set_wallpaper.sh — Rofi wallpaper picker (static or dynamic slideshow).
# Predates Prisme (see prisme-src/), still used to configure slideshow mode
# (duration, filter, image selection). Writes the state to
# wallpaper-playlist.json; it's restore_wallpaper.sh and
# wallpaper-slideshow.service that apply it.
#
# State machine driven by the `step` variable:
#   1        mode choice (Static/Dynamic)
#   2-5      Dynamic branch: filter -> duration -> image selection -> write + (re)start the service
#   20-21    Static branch:  filter -> single image selection -> immediate apply
# =========================================================
# Source folder configurable via ~/.config/prisme/wallpapers.conf, like in
# Prisme and the other scripts in this pipeline.
WALL_DIR="$HOME/Images/Wallpapers"
WALLPAPERS_CONF="$HOME/.config/prisme/wallpapers.conf"
if [[ -f "$WALLPAPERS_CONF" ]]; then
    configured="$(grep -vE '^[[:space:]]*(#|$)' "$WALLPAPERS_CONF" | head -n1)"
    [[ -n "$configured" ]] && WALL_DIR="${configured/#\~\//$HOME/}"
fi
CACHE_DIR="$HOME/.cache/filtered_wallpapers"
RASI_THEME="$HOME/.config/rofi/wallpaper.rasi"
RASI_MODE="$HOME/.config/rofi/wallpaper-mode.rasi"
PLAYLIST_FILE="$HOME/.config/hypr/wallpaper-playlist.json"

if ! pidof awww-daemon >/dev/null; then
    awww-daemon &
    sleep 0.5
fi

apply_wall() {
    awww img "$1" \
        --transition-type wipe \
        --transition-angle 30 \
        --transition-fps 45 \
        --transition-duration 1
}

step=1
MODE=""
FILTER=""
DURATION=""
CHOSEN=""

while true; do
    case $step in
        # Step 1: mode choice, common to both branches
        1)
            MODE=$(printf "Static\nDynamic" | rofi -dmenu \
                -theme "$RASI_MODE" \
                -mesg "Wallpaper Mode" \
                -name "wallpaper-picker" \
                -no-show-icons \
                -no-custom \
                -lines 2)
            [ -z "$MODE" ] && exit 0
            [ "$MODE" = "Dynamic" ] && step=2 || step=20
            ;;

        # ── DYNAMIC ──────────────────────────────────────────────
        # Step 2: filter (originals or filtered thumbnails from cache)
        2)
            FILTER=$(printf "Original\nFiltered" | rofi -dmenu \
                -theme "$RASI_MODE" \
                -mesg "Filter" \
                -name "wallpaper-picker" \
                -no-show-icons \
                -no-custom \
                -lines 2)
            [ -z "$FILTER" ] && step=1 && continue
            step=3
            ;;

        # Step 3: display duration for each image (seconds)
        3)
            DURATION=$(rofi -dmenu \
                -p "Duration (seconds)" \
                -name "wallpaper-duration" \
                -no-show-icons \
                -lines 0 \
                -theme-str 'window { width: 400px; height: 60px; } mainbox { children: [ inputbar ]; }' \
                < /dev/null)
            [ -z "$DURATION" ] && step=2 && continue
            [[ "$DURATION" =~ ^[0-9]+$ ]] || DURATION=120
            step=4
            ;;

        # Step 4: multi-select the images included in the slideshow
        4)
            SRC_DIR="$WALL_DIR"
            [ "$FILTER" = "Filtered" ] && SRC_DIR="$CACHE_DIR"

            CHOSEN=$(
                for img in "$SRC_DIR"/*; do
                    [[ "$img" =~ \.(jpg|jpeg|png|webp|PNG|JPG)$ ]] || continue
                    printf "%s\0icon\x1f%s\n" "$(basename "$img")" "$img"
                done | rofi -dmenu -i -multi-select \
                    -theme "$RASI_THEME" \
                    -p "Slideshow" \
                    -name "wallpaper-picker" \
                    -mesg "Shift+Enter to select · Enter to validate"
            )
            [ -z "$CHOSEN" ] && [ $? -ne 0 ] && step=3 && continue
            step=5
            ;;

        # Step 5: writes the JSON playlist (all images in the folder if no
        # explicit selection) and (re)starts the slideshow service
        5)
            if [ -z "$CHOSEN" ]; then
                SRC_DIR="$WALL_DIR"
                [ "$FILTER" = "Filtered" ] && SRC_DIR="$CACHE_DIR"
                mapfile -t walls < <(find "$SRC_DIR" -maxdepth 1 \
                    -iregex '.*\.\(jpg\|jpeg\|png\|webp\)' -printf '%f\n')
            else
                mapfile -t walls <<< "$CHOSEN"
            fi

            python3 -c "
import json, sys
duration = int(sys.argv[1])
source = sys.argv[2]
walls = [w for w in sys.argv[3:] if w]
with open('$PLAYLIST_FILE', 'w') as f:
    json.dump({'mode': 'dynamic', 'duration': duration, 'source': source, 'walls': walls}, f)
" "$DURATION" "$SRC_DIR" "${walls[@]}"

            systemctl --user restart wallpaper-slideshow.service
            exit 0
            ;;

        # ── STATIC ───────────────────────────────────────────────
        # Step 20: filter (originals or filtered thumbnails from cache)
        20)
            FILTER=$(printf "Original\nFiltered" | rofi -dmenu \
                -theme "$RASI_MODE" \
                -mesg "Filter" \
                -name "wallpaper-picker" \
                -no-show-icons \
                -no-custom \
                -lines 2)
            [ -z "$FILTER" ] && step=1 && continue
            step=21
            ;;

        # Step 21: single image selection, immediate apply, and stops the
        # slideshow service (the two modes are mutually exclusive)
        21)
            SRC_DIR="$WALL_DIR"
            [ "$FILTER" = "Filtered" ] && SRC_DIR="$CACHE_DIR"

            SELECTED=$(
                for img in "$SRC_DIR"/*; do
                    [[ "$img" =~ \.(jpg|jpeg|png|webp|PNG|JPG)$ ]] || continue
                    printf "%s\0icon\x1f%s\n" "$(basename "$img")" "$img"
                done | rofi -dmenu -i \
                    -theme "$RASI_THEME" \
                    -p "Wallpaper" \
                    -name "wallpaper-picker"
            )
            [ -z "$SELECTED" ] && step=20 && continue

            systemctl --user stop wallpaper-slideshow.service
            python3 -c "
import json
with open('$PLAYLIST_FILE', 'w') as f:
    json.dump({'mode': 'static', 'walls': ['$SELECTED']}, f)
"
            apply_wall "$SRC_DIR/$SELECTED"
            exit 0
            ;;
    esac
done
