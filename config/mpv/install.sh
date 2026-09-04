#!/usr/bin/env bash
set -Eeuo pipefail

GREEN="\e[32m"
RESET="\e[0m"

ok() { echo -e "${GREEN}[ OK ]${RESET}  $*"; }

# 1. Install mpv
if command -v dnf &> /dev/null; then
    sudo dnf install -y mpv
elif command -v pacman &> /dev/null; then
    sudo pacman -S --noconfirm mpv
elif command -v apt-get &> /dev/null; then
    sudo apt-get install -y mpv
fi

# 2. Symlinks
DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
mkdir -p ~/.config/mpv

safe_link() {
    local src=$1
    local dest=$2
    if [ -L "$dest" ] || [ -f "$dest" ]; then
        rm -rf "$dest"
    fi
    ln -s "$src" "$dest"
}

safe_link "$DOTFILES_DIR/config/mpv/mpv.conf" ~/.config/mpv/mpv.conf

ok "mpv configured."
