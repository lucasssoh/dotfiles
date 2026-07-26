#!/usr/bin/env bash
set -e

BLUE="\e[34m"
GREEN="\e[32m"
RESET="\e[0m"

info() { echo -e "${BLUE}[INFO]${RESET}  $*"; }
ok()   { echo -e "${GREEN}[ OK ]${RESET}  $*"; }

FONT_DIR="$HOME/.local/share/fonts"
mkdir -p "$FONT_DIR"

# Liste des polices à installer (Noms exacts pour l'URL GitHub)
# On utilise un tableau pour pouvoir en ajouter d'autres facilement
FONTS=("JetBrainsMono" "Iosevka" "CascadiaCode")

for FONT in "${FONTS[@]}"; do
    # Vérification si la police existe déjà (on ignore la casse avec -i)
    if fc-list : family | grep -iq "$FONT"; then
        info "$FONT is already installed."
    else
        info "Downloading $FONT Nerd Font..."
        # On télécharge directement dans /tmp avec le nom de la police
        curl -L "https://github.com/ryanoasis/nerd-fonts/releases/latest/download/${FONT}.zip" -o "/tmp/${FONT}.zip"

        info "Extracting $FONT..."
        # On crée un sous-dossier par police pour garder ton dossier ~/.local/share/fonts propre
        mkdir -p "$FONT_DIR/$FONT"
        unzip -o "/tmp/${FONT}.zip" -d "$FONT_DIR/$FONT"

        rm "/tmp/${FONT}.zip"
        ok "$FONT installed successfully."

        # On marque qu'on a besoin de rafraîchir le cache
        NEEDS_CACHE_RELOAD=true
    fi
done

# On ne rafraîchit le cache qu'une seule fois à la fin si nécessaire
if [ "$NEEDS_CACHE_RELOAD" = true ]; then
    info "Updating font cache..."
    fc-cache -fv
    ok "All fonts are ready."
else
    info "No new fonts to install."
fi
