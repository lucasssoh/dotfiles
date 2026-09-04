#!/usr/bin/env bash
set -Eeuo pipefail

BLUE="\e[34m"
GREEN="\e[32m"
RESET="\e[0m"

info() { echo -e "${BLUE}[INFO]${RESET}  $*"; }
ok()   { echo -e "${GREEN}[ OK ]${RESET}  $*"; }

info "Installing MangoHud + GOverlay..."

if command -v dnf &> /dev/null; then
    sudo dnf install -y mangohud goverlay
elif command -v pacman &> /dev/null; then
    sudo pacman -S --noconfirm mangohud goverlay
elif command -v apt-get &> /dev/null; then
    sudo apt-get update
    sudo apt-get install -y mangohud goverlay
fi

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

mkdir -p ~/.config/MangoHud

safe_link() {
    local src=$1
    local dest=$2

    if [ -L "$dest" ] || [ -f "$dest" ]; then
        rm -rf "$dest"
    fi

    ln -s "$src" "$dest"
}

info "Linking MangoHud config..."
safe_link \
    "$DOTFILES_DIR/config/mangohud/MangoHud.conf" \
    ~/.config/MangoHud/MangoHud.conf

ok "Done."
info "Re-login required for environment.d to take effect."
