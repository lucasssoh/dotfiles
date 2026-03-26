#!/usr/bin/env bash
set -e

FONT_DIR="$HOME/.local/share/fonts"
mkdir -p "$FONT_DIR"

# Liste des polices à installer (Noms exacts pour l'URL GitHub)
# On utilise un tableau pour pouvoir en ajouter d'autres facilement
FONTS=("JetBrainsMono" "Iosevka" "CascadiaCode")

for FONT in "${FONTS[@]}"; do
    # Vérification si la police existe déjà (on ignore la casse avec -i)
    if fc-list : family | grep -iq "$FONT"; then
        echo "[INFO] $FONT est déjà installé."
    else
        echo "[INFO] Téléchargement de $FONT Nerd Font..."
        # On télécharge directement dans /tmp avec le nom de la police
        curl -L "https://github.com/ryanoasis/nerd-fonts/releases/latest/download/${FONT}.zip" -o "/tmp/${FONT}.zip"
        
        echo "[INFO] Extraction de $FONT..."
        # On crée un sous-dossier par police pour garder ton dossier ~/.local/share/fonts propre
        mkdir -p "$FONT_DIR/$FONT"
        unzip -o "/tmp/${FONT}.zip" -d "$FONT_DIR/$FONT"
        
        rm "/tmp/${FONT}.zip"
        echo "[OK] $FONT installé avec succès."
        
        # On marque qu'on a besoin de rafraîchir le cache
        NEEDS_CACHE_RELOAD=true
    fi
done

# On ne rafraîchit le cache qu'une seule fois à la fin si nécessaire
if [ "$NEEDS_CACHE_RELOAD" = true ]; then
    echo "[INFO] Mise à jour du cache des polices..."
    fc-cache -fv
    echo "[DONE] Toutes les polices sont prêtes."
else
    echo "[INFO] Aucune nouvelle police à installer."
fi
