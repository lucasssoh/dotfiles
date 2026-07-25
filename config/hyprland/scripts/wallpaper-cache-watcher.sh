#!/usr/bin/env bash
# =========================================================
# wallpaper-cache-watcher.sh — maintient à jour le cache d'images
# "filtrées" (recadrées/étendues au format de l'écran actif, sans jamais
# rogner l'axe qui porterait le sujet principal), appliqué automatiquement
# par Prisme (prisme-src/src/apply.rs) quand il est disponible, et par le
# mode "Filtered" de l'ancien set_wallpaper.sh. Lancé par l'autostart
# Hyprland (hyprland.lua), tourne en continu.
#
# Le traitement par image lui-même (wallpaper-filter, ~/.local/bin/) est
# natif -- binaire Rust compilé depuis prisme-src/src/bin/wallpaper-
# filter.rs (même crate que Prisme, cf. install.sh), pas un script bash
# qui rappellerait ImageMagick plusieurs fois par image. Ce script-ci ne
# fait que l'orchestration : surveillance inotify, passe initiale
# parallèle, marqueur de version de cache.
# =========================================================
# Dossier source configurable via ~/.config/prisme/wallpapers.conf (une
# ligne, chemin absolu ou préfixé par ~/) -- même fichier lu par Prisme
# (prisme-src/src/wallpapers.rs) et les autres scripts de ce pipeline,
# pour n'avoir qu'un seul dossier à changer. Repli sur le défaut si le
# fichier est absent, vide, ou ne contient que des commentaires.
WALL_DIR="$HOME/Images/Wallpapers"
WALLPAPERS_CONF="$HOME/.config/prisme/wallpapers.conf"
if [[ -f "$WALLPAPERS_CONF" ]]; then
    configured="$(grep -vE '^[[:space:]]*(#|$)' "$WALLPAPERS_CONF" | head -n1)"
    [[ -n "$configured" ]] && WALL_DIR="${configured/#\~\//$HOME/}"
fi
CACHE_DIR="$HOME/.cache/filtered_wallpapers"
FILTER_BIN="$HOME/.local/bin/wallpaper-filter"

mkdir -p "$CACHE_DIR"

# Le test de fraîcheur de wallpaper-filter ne compare que les mtime
# source/cache : il ne peut pas voir un changement d'ALGORITHME de filtre,
# seulement un changement d'image source. Sans ce marqueur, les fichiers
# déjà en cache garderaient indéfiniment le rendu de l'ancienne version du
# filtre. À incrémenter à chaque changement du pipeline dans
# prisme-src/src/bin/wallpaper-filter.rs -- purge ciblée (pas un `rm -rf`
# du dossier entier) pour ne jamais toucher au marqueur lui-même ni sortir
# de CACHE_DIR. Fait ici, avant la boucle parallèle ci-dessous, et nulle
# part ailleurs : wallpaper-filter est lancé en parallèle (~30 instances
# via `&` + `wait`), un test-et-purge par instance ferait courir un race
# (l'une purgerait ce qu'une autre vient d'écrire).
FILTER_VERSION=4
VERSION_FILE="$CACHE_DIR/.filter-version"
if [[ "$(cat "$VERSION_FILE" 2>/dev/null)" != "$FILTER_VERSION" ]]; then
    find "$CACHE_DIR" -maxdepth 1 -type f \
        \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o -iname "*.webp" \) \
        -delete
    printf '%s\n' "$FILTER_VERSION" > "$VERSION_FILE"
fi

# Passe initiale : génère le cache pour toutes les images déjà présentes
while IFS= read -r -d '' img; do
    "$FILTER_BIN" "$img" &
done < <(find -L "$WALL_DIR" -maxdepth 1 -type f \
    \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o -iname "*.webp" \) \
    -print0)

wait

# Surveillance continue : régénère le cache dès qu'une image est ajoutée
# ou modifiée dans le dossier de wallpapers
inotifywait -m -e close_write,moved_to --format '%w%f' "$(readlink -f "$WALL_DIR")" | \
    while read -r filepath; do
        "$FILTER_BIN" "$filepath" &
    done
