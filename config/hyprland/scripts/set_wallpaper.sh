#!/usr/bin/env bash
# =========================================================
# set_wallpaper.sh — sélecteur de fond d'écran Rofi (statique ou
# diaporama dynamique). Antérieur à Prisme (cf. prisme-src/), toujours
# utilisé pour configurer le mode diaporama (durée, filtre, sélection
# des images). Écrit l'état dans wallpaper-playlist.json ; c'est
# restore_wallpaper.sh et wallpaper-slideshow.service qui l'appliquent.
#
# Machine à états pilotée par la variable `step` :
#   1        choix du mode (Static/Dynamic)
#   2-5      branche Dynamic : filtre -> durée -> sélection d'images -> écriture + (re)démarrage du service
#   20-21    branche Static  : filtre -> sélection d'une image -> application immédiate
# =========================================================
# Dossier source configurable via ~/.config/prisme/wallpapers.conf, comme
# dans Prisme et les autres scripts de ce pipeline.
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
        # Étape 1 : choix du mode, commune aux deux branches
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
        # Étape 2 : filtre (originaux ou vignettes filtrées en cache)
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

        # Étape 3 : durée d'affichage de chaque image (secondes)
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

        # Étape 4 : sélection multiple des images incluses dans le diaporama
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

        # Étape 5 : écrit la playlist JSON (toutes les images du dossier si
        # aucune sélection explicite) et (re)démarre le service de diaporama
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
        # Étape 20 : filtre (originaux ou vignettes filtrées en cache)
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

        # Étape 21 : sélection d'une image unique, application immédiate et
        # arrêt du service de diaporama (les deux modes sont mutuellement exclusifs)
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
