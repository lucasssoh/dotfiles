#!/usr/bin/env bash
# Symlinks the repo's wallpapers folder to ~/Images/Wallpapers, cleanly
# replacing any pre-existing folder or link at that location.
set -e

echo "[INFO] Configuration des wallpapers"

# Absolute repo path: from config/hyprland/, the repo root is two levels
# up (../..)
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WALLPAPERS_SRC="$REPO_ROOT/wallpapers"
WALLPAPERS_DST="$HOME/Images/Wallpapers"

# 1. Check the source
if [ ! -d "$WALLPAPERS_SRC" ]; then
    echo "[ERREUR] Dossier source introuvable : $WALLPAPERS_SRC"
    exit 1
fi

# 2. Clean up the destination to avoid nested folders:
# a real existing folder is renamed to .bak as a precaution...
if [ -d "$WALLPAPERS_DST" ] && [ ! -L "$WALLPAPERS_DST" ]; then
    mv "$WALLPAPERS_DST" "${WALLPAPERS_DST}.bak"
fi

# ...then any remaining symlink (valid or broken) is removed
rm -rf "$WALLPAPERS_DST"

# 3. Create the clean symlink
mkdir -p "$HOME/Images"
ln -sfn "$WALLPAPERS_SRC" "$WALLPAPERS_DST"

echo "[OK] Lien créé : $WALLPAPERS_DST -> $WALLPAPERS_SRC"
