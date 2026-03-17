#!/bin/bash

# 1. Installation de Neovim
if ! command -v nvim &> /dev/null; then
    echo "[INFO] Installation de Neovim..."
    if command -v dnf &> /dev/null; then
        sudo dnf install -y neovim
    elif command -v apt-get &> /dev/null; then
        sudo apt-get install -y neovim
    fi
fi

# 2. Liens symboliques
MODULE_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
mkdir -p ~/.config/nvim

safe_link() {
    local src=$1
    local dest=$2
    [ -L "$dest" ] || [ -f "$dest" ] && rm -rf "$dest"
    ln -s "$src" "$dest"
}

safe_link "$MODULE_DIR/init.lua" ~/.config/nvim/init.lua

echo "[OK] Neovim est configuré."
