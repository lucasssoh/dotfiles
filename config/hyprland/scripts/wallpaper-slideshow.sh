#!/usr/bin/env bash
# =========================================================
# wallpaper-slideshow.sh — boucle infinie de diaporama de fond d'écran.
# Lit la playlist (durée, source, liste d'images) écrite par
# set_wallpaper.sh/Prisme, mélange l'ordre à chaque cycle complet, et
# applique chaque image via awww. Lancé en service systemd --user
# (cf. systemd/wallpaper-slideshow.service), démarré/arrêté par
# restore_wallpaper.sh et slideshow-fullscreen-guard.sh selon le mode
# et l'état plein écran.
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

# Mélange de Fisher-Yates : évite de rejouer la playlist dans le même ordre
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

# Playlist trouvée : charge durée/source/images depuis le JSON. Sinon,
# repli sur toutes les images de WALL_DIR avec une durée par défaut.
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
        -iregex '.*\.\(jpg\|jpeg\|png\|webp\)' -printf '%f\n')
fi

[ ${#walls[@]} -eq 0 ] && exit 1

# Boucle infinie : un ordre mélangé par cycle complet de la playlist
while true; do
    mapfile -t shuffled < <(shuffle "${walls[@]}")
    for img in "${shuffled[@]}"; do
        apply_wall "$SOURCE/$img"
        sleep "$DURATION"
    done
done
