#!/usr/bin/env bash
set -e

# 1. Installer Tmux
if command -v dnf &> /dev/null; then
    sudo dnf install -y tmux wl-clipboard
elif command -v pacman &> /dev/null; then
    sudo pacman -S --noconfirm tmux wl-clipboard
elif command -v apt-get &> /dev/null; then
    sudo apt-get update
    sudo apt-get install -y tmux wl-clipboard
fi

# 2. Liens symboliques
DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

safe_link() {
    local src=$1
    local dest=$2
    if [ -L "$dest" ] || [ -f "$dest" ]; then
        rm -rf "$dest"
    fi
    ln -s "$src" "$dest"
}

# Tmux cherche sa config à la racine de ton home
safe_link "$DOTFILES_DIR/config/tmux/.tmux.conf" ~/.tmux.conf

echo "[OK] Tmux configuré"
