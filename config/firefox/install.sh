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

# 1. Install Firefox if needed
pkg_ensure firefox

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
# Root-owned, so deferred rather than prompting in user scope. The policy
# only sets the default search engine; Firefox works without it.
sudo_maybe mkdir -p /etc/firefox/policies
sudo_maybe ln -sf "$DOTFILES_DIR/config/firefox/policies.json" /etc/firefox/policies/policies.json

# 3. Env vars for Wayland/Hyprland integration
mkdir -p ~/.config/environment.d
safe_link "$DOTFILES_DIR/config/firefox/firefox.conf" ~/.config/environment.d/firefox.conf

ok "Firefox configured."
