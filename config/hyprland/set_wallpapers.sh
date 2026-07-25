#!/usr/bin/env bash
# Symlinke le dossier de wallpapers du repo vers ~/Images/Wallpapers, en
# remplaçant proprement tout dossier ou lien préexistant à cet emplacement.
set -e

echo "[INFO] Configuration des wallpapers"

# Chemin absolu du repo : depuis config/hyprland/, la racine du repo est
# deux niveaux au-dessus (../..)
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WALLPAPERS_SRC="$REPO_ROOT/wallpapers"
WALLPAPERS_DST="$HOME/Images/Wallpapers"

# 1. Vérification de la source
if [ ! -d "$WALLPAPERS_SRC" ]; then
    echo "[ERREUR] Dossier source introuvable : $WALLPAPERS_SRC"
    exit 1
fi

# 2. Nettoyage de la destination pour éviter les dossiers imbriqués :
# un vrai dossier existant est renommé en .bak par sécurité...
if [ -d "$WALLPAPERS_DST" ] && [ ! -L "$WALLPAPERS_DST" ]; then
    mv "$WALLPAPERS_DST" "${WALLPAPERS_DST}.bak"
fi

# ...puis tout lien symbolique restant (valide ou cassé) est supprimé
rm -rf "$WALLPAPERS_DST"

# 3. Création du lien symbolique propre
mkdir -p "$HOME/Images"
ln -sfn "$WALLPAPERS_SRC" "$WALLPAPERS_DST"

echo "[OK] Lien créé : $WALLPAPERS_DST -> $WALLPAPERS_SRC"
