#!/usr/bin/env bash
set -e

echo "[INFO] Configuration des wallpapers"

# Racine du repo (2 niveaux au-dessus du script)
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

WALLPAPERS_SRC="$REPO_ROOT/wallpapers"
WALLPAPERS_DST="$HOME/Images/Wallpapers"

if [ ! -d "$WALLPAPERS_SRC" ]; then
    echo "[ERREUR] Dossier source introuvable: $WALLPAPERS_SRC"
    exit 1
fi

mkdir -p "$HOME/Images"

# Remplacement propre du lien
ln -sfn "$WALLPAPERS_SRC" "$WALLPAPERS_DST"

echo "[OK] Wallpapers liés : $WALLPAPERS_DST -> $WALLPAPERS_SRC"
