#!/bin/bash

# Détection du gestionnaire pour installer Alacritty ici
if command -v dnf &> /dev/null; then
    INSTALL="sudo dnf install -y"
elif command -v pacman &> /dev/null; then
    INSTALL="sudo pacman -S --noconfirm"
elif command -v apt-get &> /dev/null; then
    INSTALL="sudo apt-get install -y"
fi

echo "[INFO] Installation d'Alacritty..."
$INSTALL alacritty

# Liens symboliques
MODULE_DIR=$(pwd)
mkdir -p ~/.config/alacritty
ln -sf "$MODULE_DIR/alacritty.toml" ~/.config/alacritty/alacritty.toml

mkdir -p ~/.config/alacritty/themes
git clone https://github.com/alacritty/alacritty-theme ~/.config/alacritty/themes

echo "[OK] Alacritty est prêt."
