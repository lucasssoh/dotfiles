#!/usr/bin/env bash
set -e

# 1. Installer Kitty
if command -v dnf &> /dev/null; then
    # Kitty est dans les dépôts officiels de Fedora, pas besoin de COPR
    sudo dnf install -y kitty
elif command -v pacman &> /dev/null; then
    sudo pacman -S --noconfirm kitty
elif command -v apt-get &> /dev/null; then
    sudo apt-get update
    sudo apt-get install -y kitty
fi

# 2. Liens symboliques
# On récupère le chemin racine des dotfiles (2 niveaux au-dessus du script)
DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
mkdir -p ~/.config/kitty

safe_link() {
    local src=$1
    local dest=$2
    if [ -L "$dest" ] || [ -f "$dest" ]; then
        rm -rf "$dest"
    fi
    ln -s "$src" "$dest"
}

# Lier la config kitty.conf
# Assure-toi que ton fichier kitty.conf est bien dans config/kitty/
safe_link "$DOTFILES_DIR/config/kitty/kitty.conf" ~/.config/kitty/kitty.conf

echo "[OK] Kitty configuré avec succès"
