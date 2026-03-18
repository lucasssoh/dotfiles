#!/usr/bin/env bash
set -e

# 1. Installer outils shell
if command -v dnf &> /dev/null; then
    sudo dnf install -y fzf zoxide
elif command -v pacman &> /dev/null; then
    sudo pacman -S --noconfirm fzf zoxide
elif command -v apt-get &> /dev/null; then
    sudo apt-get install -y fzf zoxide
fi

# 2. Installer Starship si besoin
if ! command -v starship &> /dev/null; then
    echo "[INFO] Installation de Starship..."
    curl -sS https://starship.rs/install.sh | sh -s -- -y
fi

# 3. Liens symboliques
DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
mkdir -p ~/.config

safe_link() {
    local src=$1
    local dest=$2
    if [ -L "$dest" ] || [ -f "$dest" ]; then
        rm -rf "$dest"
    fi
    ln -s "$src" "$dest"
}

safe_link "$DOTFILES_DIR/config/bash/.bashrc" ~/.bashrc
safe_link "$DOTFILES_DIR/config/bash/.bash_aliases" ~/.bash_aliases
safe_link "$DOTFILES_DIR/config/bash/starship.toml" ~/.config/starship.toml

echo "[OK] Bash et Starship configurés"