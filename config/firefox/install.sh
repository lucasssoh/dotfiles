#!/usr/bin/env bash
set -e

BLUE="\e[34m"
GREEN="\e[32m"
RESET="\e[0m"

info() { echo -e "${BLUE}[INFO]${RESET}  $*"; }
ok()   { echo -e "${GREEN}[ OK ]${RESET}  $*"; }

# 1. Install Firefox if needed
if ! command -v firefox &> /dev/null; then
    info "Installing Firefox..."
    if command -v dnf &> /dev/null; then
        sudo dnf install -y firefox
    elif command -v apt-get &> /dev/null; then
        sudo apt-get install -y firefox
    fi
fi

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

safe_link() {
    local src=$1
    local dest=$2
    if [ -L "$dest" ] || [ -f "$dest" ]; then
        rm -rf "$dest"
    fi
    ln -s "$src" "$dest"
}

# 2. System policy: Google as default, regardless of the Fedora region
sudo mkdir -p /etc/firefox/policies
sudo ln -sf "$DOTFILES_DIR/config/firefox/policies.json" /etc/firefox/policies/policies.json

# 3. Env vars for Wayland/Hyprland integration
mkdir -p ~/.config/environment.d
safe_link "$DOTFILES_DIR/config/firefox/firefox.conf" ~/.config/environment.d/firefox.conf

ok "Firefox configured."
