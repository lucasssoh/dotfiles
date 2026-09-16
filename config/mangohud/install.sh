#!/usr/bin/env bash
set -Eeuo pipefail

# Package helper: queries before it installs, so an already-provisioned
# machine performs zero package-manager calls and never prompts for sudo.
. "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../../scripts/lib/pkg.sh"

BLUE="\e[34m"
GREEN="\e[32m"
RESET="\e[0m"

info() { echo -e "${BLUE}[INFO]${RESET}  $*"; }
ok()   { echo -e "${GREEN}[ OK ]${RESET}  $*"; }

info "Installing MangoHud + GOverlay..."

pkg_ensure mangohud goverlay

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
