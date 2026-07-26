#!/usr/bin/env bash
set -e

GREEN="\e[32m"
RESET="\e[0m"

ok() { echo -e "${GREEN}[ OK ]${RESET}  $*"; }

# 1. Installer fuzzel
if command -v dnf &> /dev/null; then
    sudo dnf install -y fuzzel
elif command -v pacman &> /dev/null; then
    sudo pacman -S --noconfirm fuzzel
elif command -v apt-get &> /dev/null; then
    sudo apt-get install -y fuzzel
fi

# 2. Liens symboliques
DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
mkdir -p ~/.config/fuzzel

safe_link() {
    local src=$1
    local dest=$2
    if [ -L "$dest" ] || [ -f "$dest" ]; then
        rm -rf "$dest"
    fi
    ln -s "$src" "$dest"
}

safe_link "$DOTFILES_DIR/config/fuzzel/fuzzel.ini" ~/.config/fuzzel/fuzzel.ini

ok "Fuzzel configured."
