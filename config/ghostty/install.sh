#!/usr/bin/env bash
set -e

BLUE="\e[34m"
GREEN="\e[32m"
YELLOW="\e[33m"
RESET="\e[0m"

info() { echo -e "${BLUE}[INFO]${RESET}  $*"; }
ok()   { echo -e "${GREEN}[ OK ]${RESET}  $*"; }
warn() { echo -e "${YELLOW}[WARN]${RESET}  $*"; }

# --- 1. INSTALLATION DE GHOSTTY ---
if command -v dnf &> /dev/null; then
    info "Configuring the Terra repo for Ghostty..."
    # On installe terra-release. Si la version 43 n'est pas dispo, on pointe sur la 42.

    sudo dnf install -y --nogpgcheck --repofrompath 'terra,https://repos.fyralabs.com/terra$releasever' terra-release
    sudo dnf install -y ghostty

elif command -v pacman &> /dev/null; then
    sudo pacman -S --noconfirm ghostty
elif command -v apt-get &> /dev/null; then
    # Ghostty est souvent en PPA ou nécessite de compiler sur Debian/Ubuntu
    warn "Ghostty often requires building from source on Debian-based systems. Installing via Flatpak instead."
    flatpak install -y flathub com.mitchellh.ghostty
fi

# --- 2. CONFIGURATION DES DOTFILES ---
# On récupère le chemin racine (ajuste le nombre de /.. selon ta structure réelle)
DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
mkdir -p ~/.config/ghostty

safe_link() {
    local src=$1
    local dest=$2
    if [ -L "$dest" ] || [ -f "$dest" ]; then
        rm -rf "$dest"
    fi
    ln -s "$src" "$dest"
    info "Linked: $dest -> $src"
}

# Lier le fichier de config Ghostty
# On suppose que tu as créé un dossier config/ghostty/ dans tes dotfiles
if [ -f "$DOTFILES_DIR/config/ghostty/config" ]; then
    safe_link "$DOTFILES_DIR/config/ghostty/config" ~/.config/ghostty/config
else
    warn "Source file not found: $DOTFILES_DIR/config/ghostty/config"
fi

ok "Ghostty installed and configured successfully."
