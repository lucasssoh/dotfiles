#!/usr/bin/env bash
# Builds ~/Images/Wallpapers as the union of two sources:
#   - the repo's wallpapers/ folder (4 defaults, public, versioned with dotfiles)
#   - a private wallpapers-private/wallpapers/ repo (optional, the bulk collection)
# ~/Images/Wallpapers itself becomes a real directory full of symlinks (one
# per image), so everything downstream (prisme/wallpapers.conf and the
# scripts that follow it) keeps reading a single flat folder unchanged.
set -e

echo "[INFO] Configuration des wallpapers"

# Absolute repo path: from config/hyprland/, the repo root is two levels
# up (../..)
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DOTFILES_SRC="$REPO_ROOT/wallpapers"
PRIVATE_SRC="$HOME/code/wallpapers-private/wallpapers"
WALLPAPERS_DST="$HOME/Images/Wallpapers"

# 1. Check the sources
if [ ! -d "$DOTFILES_SRC" ]; then
    echo "[ERREUR] Dossier source introuvable : $DOTFILES_SRC"
    exit 1
fi
if [ ! -d "$PRIVATE_SRC" ]; then
    echo "[INFO] Repo privé absent ($PRIVATE_SRC) : seuls les défauts dotfiles seront utilisés"
fi

# 2. Clean up the destination to avoid stale symlinks or a leftover plain
# folder from before this script merged two sources:
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
for src in "$DOTFILES_SRC" "$PRIVATE_SRC"; do
    [ -d "$src" ] || continue
    for f in "$src"/*; do
        [ -f "$f" ] || continue
        ln -sfn "$f" "$WALLPAPERS_DST/$(basename "$f")"
        count=$((count + 1))
    done
done

echo "[OK] $WALLPAPERS_DST reconstruit ($count wallpapers) depuis :"
echo "       - $DOTFILES_SRC"
[ -d "$PRIVATE_SRC" ] && echo "       - $PRIVATE_SRC"
