#!/usr/bin/env bash
set -e

echo "[INFO] Installation des dépendances..."

# =========================
# PACKAGE MANAGER
# =========================
if command -v dnf &> /dev/null; then
    sudo dnf install -y fzf zoxide ripgrep fd-find make gcc zsh
elif command -v pacman &> /dev/null; then
    sudo pacman -S --noconfirm fzf zoxide ripgrep fd make gcc zsh
elif command -v apt-get &> /dev/null; then
    sudo apt-get update
    sudo apt-get install -y fzf ripgrep fd-find make gcc zsh

    if ! command -v zoxide &> /dev/null; then
        curl -sS https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh | sh
    fi
fi

# =========================
# STARSHIP
# =========================
if ! command -v starship &> /dev/null; then
    echo "[INFO] Installation de Starship..."
    curl -sS https://starship.rs/install.sh | sh -s -- -y
fi

# =========================
# ZSH PLUGINS
# =========================
ZSH_PLUGIN_DIR="$HOME/.zsh"
mkdir -p "$ZSH_PLUGIN_DIR"

clone_if_not_exists() {
    local repo=$1
    local dest=$2

    if [ ! -d "$dest" ]; then
        git clone "$repo" "$dest"
    fi
}

clone_if_not_exists https://github.com/zsh-users/zsh-autosuggestions "$ZSH_PLUGIN_DIR/zsh-autosuggestions"
clone_if_not_exists https://github.com/zsh-users/zsh-syntax-highlighting "$ZSH_PLUGIN_DIR/zsh-syntax-highlighting"

# =========================
# DOTFILES LINK
# =========================
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

mkdir -p ~/.config/bash

# Bash (fallback + scripts)
safe_link "$DOTFILES_DIR/config/bash/.bashrc" "$HOME/.bashrc"
safe_link "$DOTFILES_DIR/config/bash/.bash_aliases" "$HOME/.bash_aliases"

# Zsh (principal)
safe_link "$DOTFILES_DIR/config/bash/.zshrc" "$HOME/.zshrc"

# Starship
safe_link "$DOTFILES_DIR/config/bash/starship.toml" "$HOME/.config/starship.toml"

# =========================
# SHELL PAR DÉFAUT
# =========================
if command -v zsh &> /dev/null; then
    if [[ "$SHELL" != *"zsh" ]]; then
        echo "[INFO] Changement du shell par défaut vers zsh..."
        chsh -s "$(which zsh)"
    fi
fi

echo "[OK] Environnement shell configuré avec succès"
