#!/usr/bin/env bash
set -e

# 1. Installer fastfetch
if command -v dnf &> /dev/null; then
    sudo dnf install -y fastfetch
elif command -v pacman &> /dev/null; then
    sudo pacman -S --noconfirm fastfetch
elif command -v apt-get &> /dev/null; then
    sudo apt-get update
    sudo apt-get install -y fastfetch
fi

# 2. Liens symboliques
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

# Lier la config JSONC et l'image
safe_link "$DOTFILES_DIR/config/fastfetch/config.jsonc" ~/.config/fastfetch/config.jsonc
safe_link "$DOTFILES_DIR/config/fastfetch/rayponce.jpg" ~/.config/fastfetch/rayponce.jpg

echo "[OK] Fastfetch configured"
