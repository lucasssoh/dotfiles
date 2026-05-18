#!/usr/bin/env bash
WALL_DIR="$HOME/Images/Wallpapers"
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
DURATION=""
CHOSEN=""

while true; do
    case $step in
        1)
            MODE=$(printf "Static\nDynamic" | rofi -dmenu \
                -theme "$RASI_MODE" \
                -p "" \
                -name "wallpaper-picker" \
                -no-show-icons \
                -no-custom \
                -lines 2)
            [ -z "$MODE" ] && exit 0
            [ "$MODE" = "Dynamic" ] && step=2 || step=10
            ;;

        2)
            DURATION=$(rofi -dmenu \
                -p "Duration" \
                -name "wallpaper-duration" \
                -no-show-icons \
                -lines 0 \
                -theme-str 'window { width: 400px; height: 60px; } mainbox { children: [ inputbar ]; }' \
                < /dev/null)
            if [ -z "$DURATION" ]; then
                step=1
                continue
            fi
            [[ "$DURATION" =~ ^[0-9]+$ ]] || DURATION=120
            step=3
            ;;

        3)
            CHOSEN=$(
                for img in "$WALL_DIR"/*; do
                    [[ "$img" =~ \.(jpg|jpeg|png|webp|PNG|JPG)$ ]] || continue
                    printf "%s\0icon\x1f%s\n" "$(basename "$img")" "$img"
                done | rofi -dmenu -i -multi-select \
                    -theme "$RASI_THEME" \
                    -p "Slideshow" \
                    -name "wallpaper-picker" \
                    -mesg "Shift+Enter to select· Enter to validate"
            )
            if [ -z "$CHOSEN" ] && [ $? -ne 0 ]; then
                step=2
                continue
            fi
            step=4
            ;;

        4)
            if [ -z "$CHOSEN" ]; then
                mapfile -t walls < <(find "$WALL_DIR" -maxdepth 1 \
                    -iregex '.*\.\(jpg\|jpeg\|png\|webp\)' -printf '%f\n')
            else
                mapfile -t walls <<< "$CHOSEN"
            fi

            python3 -c "
import json, sys
duration = int(sys.argv[1])
walls = [w for w in sys.argv[2:] if w]
with open('$PLAYLIST_FILE', 'w') as f:
    json.dump({'mode': 'dynamic', 'duration': duration, 'walls': walls}, f)
" "$DURATION" "${walls[@]}"

            systemctl --user restart wallpaper-slideshow.service
            exit 0
            ;;

        10)
            SELECTED=$(
                for img in "$WALL_DIR"/*; do
                    [[ "$img" =~ \.(jpg|jpeg|png|webp|PNG|JPG)$ ]] || continue
                    printf "%s\0icon\x1f%s\n" "$(basename "$img")" "$img"
                done | rofi -dmenu -i \
                    -theme "$RASI_THEME" \
                    -p "Wallpaper" \
                    -name "wallpaper-picker"
            )
            if [ -z "$SELECTED" ]; then
                step=1
                continue
            fi

            systemctl --user stop wallpaper-slideshow.service
            python3 -c "
import json
with open('$PLAYLIST_FILE', 'w') as f:
    json.dump({'mode': 'static', 'walls': ['$SELECTED']}, f)
"
            apply_wall "$WALL_DIR/$SELECTED"
            exit 0
            ;;
    esac
done
