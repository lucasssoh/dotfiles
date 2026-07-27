#!/usr/bin/env bash
set -e

GREEN="\e[32m"
RESET="\e[0m"

ok() { echo -e "${GREEN}[ OK ]${RESET}  $*"; }

# 1. Install fastfetch
if command -v dnf &> /dev/null; then
    sudo dnf install -y fastfetch chafa
elif command -v pacman &> /dev/null; then
    sudo pacman -S --noconfirm fastfetch chafa
elif command -v apt-get &> /dev/null; then
    sudo apt-get update
    sudo apt-get install -y fastfetch chafa
fi

# 2. Symlinks
DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
mkdir -p ~/.config/fastfetch

safe_link() {
    local src=$1
    local dest=$2
    if [ -L "$dest" ] || [ -f "$dest" ]; then
        rm -rf "$dest"
    fi
    ln -s "$src" "$dest"
}

# Link the JSONC config and the image
safe_link "$DOTFILES_DIR/config/fastfetch/config.jsonc" ~/.config/fastfetch/config.jsonc
safe_link "$DOTFILES_DIR/config/fastfetch/rayponce.jpg" ~/.config/fastfetch/rayponce.jpg

ok "Fastfetch configured."
