#!/usr/bin/env bash
set -Eeuo pipefail

# Package helper: queries before it installs, so an already-provisioned
# machine performs zero package-manager calls and never prompts for sudo.
. "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../../scripts/lib/pkg.sh"

GREEN="\e[32m"
RESET="\e[0m"

ok() { echo -e "${GREEN}[ OK ]${RESET}  $*"; }

# 1. Installer fuzzel
pkg_ensure fuzzel

# 2. Liens symboliques
DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
mkdir -p ~/.config/fuzzel

safe_link() {
    local src=$1
    local dest=$2
    if [ -L "$dest" ] || [ -f "$dest" ]; then
        rm -rf "$dest"
    fi
    ln -s "$src" "$dest"
}

safe_link "$DOTFILES_DIR/config/fuzzel/fuzzel.ini" ~/.config/fuzzel/fuzzel.ini

ok "Fuzzel configured."
