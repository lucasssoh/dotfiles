#!/bin/bash

# Détection du gestionnaire de paquets pour git et curl
if command -v dnf &> /dev/null; then
    PKGMGR="sudo dnf install -y"
elif command -v pacman &> /dev/null; then
    PKGMGR="sudo pacman -S --noconfirm"
elif command -v apt-get &> /dev/null; then
    PKGMGR="sudo apt-get install -y"
else
    echo "[ERREUR] Gestionnaire de paquets non supporté."
    exit 1
fi

echo "[INFO] Installation des bases (git, curl)..."
$PKGMGR git curl

DOTFILES_DIR=$(pwd)

# On lance les modules
for module in fonts bash wezterm; do
    if [ -d "$DOTFILES_DIR/$module" ]; then
        echo "[INFO] Lancement du module : $module"
        cd "$DOTFILES_DIR/$module" && chmod +x ./install.sh && ./install.sh
        cd "$DOTFILES_DIR"
    fi
done

echo "[OK] Installation globale terminée."
