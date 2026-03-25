#!/usr/bin/env bash
set -e

# 1. Installer outils shell et dépendances Neovim (Telescope)
echo "[INFO] Installation des dépendances..."
if command -v dnf &> /dev/null; then
    # Fedora
    sudo dnf install -y fzf zoxide ripgrep fd-find make gcc
elif command -v pacman &> /dev/null; then
    # Arch Linux
    sudo pacman -S --noconfirm fzf zoxide ripgrep fd make gcc
elif command -v apt-get &> /dev/null; then
    # Debian / Ubuntu
    sudo apt-get update
    sudo apt-get install -y fzf ripgrep fd-find make gcc
    # Zoxide n'est pas toujours sur les vieux dépôts APT, on check
    if ! command -v zoxide &> /dev/null; then
        curl -sS https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh | sh
    fi
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

# On s'assure que les dossiers parents existent
mkdir -p ~/.config/bash

safe_link "$DOTFILES_DIR/config/bash/.bashrc" "$HOME/.bashrc"
safe_link "$DOTFILES_DIR/config/bash/.bash_aliases" "$HOME/.bash_aliases"
safe_link "$DOTFILES_DIR/config/bash/starship.toml" "$HOME/.config/starship.toml"

echo "[OK] Environnement shell configuré avec succès"
