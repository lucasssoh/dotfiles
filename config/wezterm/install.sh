#!/usr/bin/env bash
set -e

# 1. Installer WezTerm
if command -v dnf &> /dev/null; then
    sudo dnf copr enable wezfurlong/wezterm-nightly -y
    sudo dnf install -y wezterm
elif command -v pacman &> /dev/null; then
    sudo pacman -S --noconfirm wezterm
elif command -v apt-get &> /dev/null; then
    curl -fsSL https://apt.fury.io/wez/gpg.key | sudo gpg --yes --dearmor -o /usr/share/keyrings/wezterm-fury.gpg
    echo 'deb [signed-by=/usr/share/keyrings/wezterm-fury.gpg] https://apt.fury.io/wez/ * *' | sudo tee /etc/apt/sources.list.d/wezterm.list
    sudo apt-get update
    sudo apt-get install -y wezterm
fi

# 2. Liens symboliques
DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
mkdir -p ~/.config/wezterm

safe_link() {
    local src=$1
    local dest=$2
    if [ -L "$dest" ] || [ -f "$dest" ]; then
        rm -rf "$dest"
    fi
    ln -s "$src" "$dest"
}

# Lier la config
safe_link "$DOTFILES_DIR/config/wezterm/wezterm.lua" ~/.wezterm.lua
safe_link "$DOTFILES_DIR/config/wezterm/wezterm.lua" ~/.config/wezterm/wezterm.lua

echo "[OK] WezTerm configuré"