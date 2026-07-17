#!/usr/bin/env bash
WALL_DIR="$HOME/Images/Wallpapers"
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
