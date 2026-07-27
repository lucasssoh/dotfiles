#!/usr/bin/env bash
set -e

GREEN="\e[32m"
RESET="\e[0m"

ok() { echo -e "${GREEN}[ OK ]${RESET}  $*"; }

# 1. Install Kitty
if command -v dnf &> /dev/null; then
    # Kitty is in Fedora's official repos, no COPR needed
    sudo dnf install -y kitty
elif command -v pacman &> /dev/null; then
    sudo pacman -S --noconfirm kitty
elif command -v apt-get &> /dev/null; then
    sudo apt-get update
    sudo apt-get install -y kitty
fi

# 2. Symlinks
# Resolve the dotfiles root path (2 levels above this script)
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

# Link the kitty.conf config
# Make sure your kitty.conf file is in config/kitty/
safe_link "$DOTFILES_DIR/config/kitty/kitty.conf" ~/.config/kitty/kitty.conf

ok "Kitty configured successfully."
