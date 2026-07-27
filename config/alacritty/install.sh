#!/bin/bash

BLUE="\e[34m"
GREEN="\e[32m"
RESET="\e[0m"

info() { echo -e "${BLUE}[INFO]${RESET}  $*"; }
ok()   { echo -e "${GREEN}[ OK ]${RESET}  $*"; }

# Detect the package manager to install Alacritty with
if command -v dnf &> /dev/null; then
    INSTALL="sudo dnf install -y"
elif command -v pacman &> /dev/null; then
    INSTALL="sudo pacman -S --noconfirm"
elif command -v apt-get &> /dev/null; then
    INSTALL="sudo apt-get install -y"
fi

info "Installing Alacritty..."
$INSTALL alacritty

# Symlinks
MODULE_DIR=$(pwd)
mkdir -p ~/.config/alacritty
ln -sf "$MODULE_DIR/alacritty.toml" ~/.config/alacritty/alacritty.toml

mkdir -p ~/.config/alacritty/themes
git clone https://github.com/alacritty/alacritty-theme ~/.config/alacritty/themes

ok "Alacritty is ready."
