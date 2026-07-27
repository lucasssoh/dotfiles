#!/usr/bin/env bash
set -e

BLUE="\e[34m"
GREEN="\e[32m"
RESET="\e[0m"

info() { echo -e "${BLUE}[INFO]${RESET}  $*"; }
ok()   { echo -e "${GREEN}[ OK ]${RESET}  $*"; }

# 1. Make sure Flatpak is installed and Flathub is enabled
info "Checking Flatpak..."
if command -v dnf &> /dev/null; then
    sudo dnf install -y flatpak
elif command -v pacman &> /dev/null; then
    sudo pacman -S --noconfirm flatpak
elif command -v apt-get &> /dev/null; then
    sudo apt-get update && sudo apt-get install -y flatpak
fi

# Add the Flathub remote if it doesn't already exist
sudo flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo

# 2. Install Zen Browser
info "Installing Zen Browser via Flatpak..."
# Using the app's ID on Flathub
sudo flatpak install -y flathub io.github.zen_browser.zen

# 3. Integration (your philosophy)
# Optional: create an alias to launch it faster from the terminal
DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# Symlinks to launch zen from the terminal and from Hyprland
sudo ln -sf /var/lib/flatpak/exports/bin/app.zen_browser.zen /usr/local/bin/zen
sudo ln -sf /var/lib/flatpak/exports/bin/app.zen_browser.zen /usr/local/bin/zen-browser

ok "Zen Browser (Flatpak) installed."
