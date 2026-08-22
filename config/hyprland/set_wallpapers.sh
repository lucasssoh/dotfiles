#!/usr/bin/env bash
# Builds ~/Images/Wallpapers as the union of the repo's own wallpapers/
# folder (4 defaults, public, versioned with dotfiles) and whatever extra
# folders are listed in prisme/wallpapers-extra.conf (e.g. a private repo
# holding the bulk of the collection -- see that file for the format).
# ~/Images/Wallpapers itself becomes a real directory full of symlinks (one
# per image), so everything downstream (prisme/wallpapers.conf and the
# scripts that follow it) keeps reading a single flat folder unchanged.
#
# One-shot/manual entry point: wallpaper-cache-watcher.sh keeps this same
# merge in sync live (watching every source folder), so this script only
# needs a (re)run by hand for the initial setup or right after editing
# wallpapers-extra.conf.
set -e

echo "[INFO] Configuration des wallpapers"

# Absolute repo path: from config/hyprland/, the repo root is two levels
# up (../..)
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DOTFILES_SRC="$REPO_ROOT/wallpapers"
WALLPAPERS_DST="$HOME/Images/Wallpapers"

# Extra source folders -- see prisme/wallpapers-extra.conf for the format.
EXTRA_SOURCES_CONF="$HOME/.config/prisme/wallpapers-extra.conf"
EXTRA_SOURCES=()
if [ -f "$EXTRA_SOURCES_CONF" ]; then
    while IFS= read -r line; do
        EXTRA_SOURCES+=("${line/#\~\//$HOME/}")
    done < <(grep -vE '^[[:space:]]*(#|$)' "$EXTRA_SOURCES_CONF")
fi

# 1. Check the sources
if [ ! -d "$DOTFILES_SRC" ]; then
    echo "[ERREUR] Dossier source introuvable : $DOTFILES_SRC"
    exit 1
fi
for src in "${EXTRA_SOURCES[@]}"; do
    [ -d "$src" ] || echo "[INFO] Dossier extra introuvable, ignoré : $src"
done

# 2. Clean up the destination to avoid stale symlinks or a leftover plain
# folder from before this script merged multiple sources:
# a real existing folder that isn't already our own symlink farm is backed
# up as a precaution...
if [ -d "$WALLPAPERS_DST" ] && [ ! -L "$WALLPAPERS_DST" ] && [ ! -f "$WALLPAPERS_DST/.wallpapers-merged" ]; then
    mv "$WALLPAPERS_DST" "${WALLPAPERS_DST}.bak"
fi
# ...anything else (a plain symlink from the old single-source setup, or
# our own farm from a previous run) is removed and rebuilt from scratch.
rm -rf "$WALLPAPERS_DST"

# 3. Rebuild the merged folder
mkdir -p "$HOME/Images" "$WALLPAPERS_DST"
touch "$WALLPAPERS_DST/.wallpapers-merged"

count=0
for src in "$DOTFILES_SRC" "${EXTRA_SOURCES[@]}"; do
    [ -d "$src" ] || continue
    for f in "$src"/*; do
        [ -f "$f" ] || continue
        ln -sfn "$f" "$WALLPAPERS_DST/$(basename "$f")"
        count=$((count + 1))
    done
done

echo "[OK] $WALLPAPERS_DST reconstruit ($count wallpapers) depuis :"
echo "       - $DOTFILES_SRC"
for src in "${EXTRA_SOURCES[@]}"; do
    [ -d "$src" ] && echo "       - $src"
done
