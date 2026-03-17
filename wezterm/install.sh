#!/bin/bash

# 1. Détection du gestionnaire et installation de WezTerm
if command -v dnf &> /dev/null; then
    # Fedora nécessite souvent le dépôt COPR pour WezTerm
    sudo dnf copr enable wezfurlong/wezterm-nightly -y
    INSTALL="sudo dnf install -y"
elif command -v pacman &> /dev/null; then
    INSTALL="sudo pacman -S --noconfirm"
elif command -v apt-get &> /dev/null; then
    # Pour Ubuntu/Debian, installation via le repo officiel WezTerm
    curl -fsSL https://apt.fury.io/wez/gpg.key | sudo gpg --yes --dearmor -o /usr/share/keyrings/wezterm-fury.gpg
    echo 'deb [signed-by=/usr/share/keyrings/wezterm-fury.gpg] https://apt.fury.io/wez/ * *' | sudo tee /etc/apt/sources.list.d/wezterm.list
    sudo apt-get update
    INSTALL="sudo apt-get install -y"
fi

echo "[INFO] Installation de WezTerm..."
$INSTALL wezterm

# --- 2. Liens symboliques ---
MODULE_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

echo "[INFO] Configuration de WezTerm depuis : $MODULE_DIR"

# WezTerm cherche souvent son fichier à la racine du HOME ou dans .config
mkdir -p ~/.config/wezterm

safe_link() {
    local src=$1
    local dest=$2
    [ -L "$dest" ] || [ -f "$dest" ] && rm -rf "$dest"
    ln -s "$src" "$dest"
}

# On lie le fichier de config (wezterm.lua)
safe_link "$MODULE_DIR/wezterm.lua" ~/.wezterm.lua
# Optionnel : aussi dans .config pour être sûr selon la version
safe_link "$MODULE_DIR/wezterm.lua" ~/.config/wezterm/wezterm.lua

echo "[OK] WezTerm est configuré."