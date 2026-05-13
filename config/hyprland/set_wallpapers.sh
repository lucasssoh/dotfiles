#!/usr/bin/env bash
set -e

echo "[INFO] Configuration des wallpapers"

# On récupère le chemin absolu du repo
# Depuis config/hyprland/, le repo root est à 2 niveaux au-dessus (../..)
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WALLPAPERS_SRC="$REPO_ROOT/wallpapers"
WALLPAPERS_DST="$HOME/Images/Wallpapers"

# 1. Vérification de la source
if [ ! -d "$WALLPAPERS_SRC" ]; then
    echo "[ERREUR] Dossier source introuvable : $WALLPAPERS_SRC"
    exit 1
fi

# 2. Nettoyage drastique pour éviter les sous-dossiers imbriqués
# Si c'est un dossier réel, on le renomme en .bak par sécurité
if [ -d "$WALLPAPERS_DST" ] && [ ! -L "$WALLPAPERS_DST" ]; then
    mv "$WALLPAPERS_DST" "${WALLPAPERS_DST}.bak"
fi

# Si c'est un lien (même cassé ou pointant ailleurs), on le supprime
rm -rf "$WALLPAPERS_DST"

# 3. Création du lien symbolique propre
mkdir -p "$HOME/Images"
ln -sfn "$WALLPAPERS_SRC" "$WALLPAPERS_DST"

echo "[OK] Lien créé : $WALLPAPERS_DST -> $WALLPAPERS_SRC"
