#!/usr/bin/env bash
set -e

FONT_DIR="$HOME/.local/share/fonts"
mkdir -p "$FONT_DIR"

if fc-list : family | grep -iq "JetBrainsMono"; then
    echo "[INFO] JetBrains Mono déjà installé"
else
    echo "[INFO] Téléchargement de JetBrains Mono Nerd Font..."
    curl -L https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.zip -o /tmp/jb.zip
    
    echo "[INFO] Installation des polices..."
    unzip -o /tmp/jb.zip -d "$FONT_DIR"
    
    echo "[INFO] Mise à jour du cache des polices..."
    fc-cache -fv
    
    rm /tmp/jb.zip
    echo "[OK] Polices installées"
fi