#!/usr/bin/env bash
set -Eeuo pipefail

# The single safe_link (scripts/lib/link.sh). It replaces the copy that used
# to live here: that one removed and re-created the link on every run, even
# when it was already correct. This one returns early, and records what it
# did so `cc-pkg-mng verify` can check it later.
. "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../../scripts/lib/link.sh"

# Package helper: queries before it installs, so an already-provisioned
# machine performs zero package-manager calls and never prompts for sudo.
. "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../../scripts/lib/pkg.sh"

BLUE="\e[34m"
GREEN="\e[32m"
RESET="\e[0m"

info() { echo -e "${BLUE}[INFO]${RESET}  $*"; }
ok()   { echo -e "${GREEN}[ OK ]${RESET}  $*"; }

# 1. Install Neovim if needed
pkg_ensure neovim

# 2. Symlinks
DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
mkdir -p ~/.config/nvim


safe_link "$DOTFILES_DIR/config/nvim/init.lua" ~/.config/nvim/init.lua
safe_link "$DOTFILES_DIR/config/nvim/lua" ~/.config/nvim/lua
safe_link "$DOTFILES_DIR/config/nvim/ftplugin" ~/.config/nvim/ftplugin
safe_link "$DOTFILES_DIR/config/nvim/colors" ~/.config/nvim/colors
ok "Neovim configured."
