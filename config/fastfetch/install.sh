#!/usr/bin/env bash
set -Eeuo pipefail

# Package helper: queries before it installs, so an already-provisioned
# machine performs zero package-manager calls and never prompts for sudo.
. "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../../scripts/lib/pkg.sh"

GREEN="\e[32m"
RESET="\e[0m"

ok() { echo -e "${GREEN}[ OK ]${RESET}  $*"; }

# 1. Install fastfetch
pkg_ensure fastfetch chafa

# 2. Symlinks
DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
mkdir -p ~/.config/fastfetch

safe_link() {
    local src=$1
    local dest=$2
    if [ -L "$dest" ] || [ -f "$dest" ]; then
        rm -rf "$dest"
    fi
    ln -s "$src" "$dest"
}

# Link the JSONC config and the image
safe_link "$DOTFILES_DIR/config/fastfetch/config.jsonc" ~/.config/fastfetch/config.jsonc
safe_link "$DOTFILES_DIR/config/fastfetch/rayponce.jpg" ~/.config/fastfetch/rayponce.jpg

ok "Fastfetch configured."
