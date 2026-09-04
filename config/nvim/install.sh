#!/usr/bin/env bash
set -Eeuo pipefail

BLUE="\e[34m"
GREEN="\e[32m"
RESET="\e[0m"

info() { echo -e "${BLUE}[INFO]${RESET}  $*"; }
ok()   { echo -e "${GREEN}[ OK ]${RESET}  $*"; }

# 1. Install Neovim if needed
if ! command -v nvim &> /dev/null; then
    info "Installing Neovim..."
    if command -v dnf &> /dev/null; then
        sudo dnf install -y neovim
    elif command -v apt-get &> /dev/null; then
        sudo apt-get install -y neovim
    fi
fi

# 2. Symlinks
DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
mkdir -p ~/.config/nvim

safe_link() {
    local src=$1
    local dest=$2
    if [ -L "$dest" ] || [ -f "$dest" ]; then
        rm -rf "$dest"
    fi
    ln -s "$src" "$dest"
}

safe_link "$DOTFILES_DIR/config/nvim/init.lua" ~/.config/nvim/init.lua
safe_link "$DOTFILES_DIR/config/nvim/lua" ~/.config/nvim/lua
safe_link "$DOTFILES_DIR/config/nvim/ftplugin" ~/.config/nvim/ftplugin
safe_link "$DOTFILES_DIR/config/nvim/colors" ~/.config/nvim/colors
ok "Neovim configured."
