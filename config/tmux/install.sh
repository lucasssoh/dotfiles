#!/usr/bin/env bash
set -e

GREEN="\e[32m"
RESET="\e[0m"

ok() { echo -e "${GREEN}[ OK ]${RESET}  $*"; }

# 1. Install Tmux
if command -v dnf &> /dev/null; then
    sudo dnf install -y tmux wl-clipboard
elif command -v pacman &> /dev/null; then
    sudo pacman -S --noconfirm tmux wl-clipboard
elif command -v apt-get &> /dev/null; then
    sudo apt-get update
    sudo apt-get install -y tmux wl-clipboard
fi

# 2. Symlinks
DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

safe_link() {
    local src=$1
    local dest=$2
    if [ -L "$dest" ] || [ -f "$dest" ]; then
        rm -rf "$dest"
    fi
    ln -s "$src" "$dest"
}

# Tmux looks for its config at the root of your home directory
safe_link "$DOTFILES_DIR/config/tmux/.tmux.conf" ~/.tmux.conf

ok "Tmux configured."
