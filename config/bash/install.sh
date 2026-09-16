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

info "Installing dependencies..."

# =========================
# PACKAGE MANAGER
# =========================
pkg_ensure fzf ripgrep make gcc zsh "$(pkg_pick fd-find fd fd-find)"

# zoxide separately: Debian/Ubuntu have no usable package for it, so it is
# the one name here that can need the upstream installer.
if [ "$(pkg_mgr)" = apt ]; then
    if ! command -v zoxide &> /dev/null; then
        # Download first, then run: a direct `curl | sh` hides a curl
        # failure (network down, 404) behind sh happily exiting 0 on empty
        # stdin.
        curl -fsSL -o /tmp/zoxide-install.sh https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh
        sh /tmp/zoxide-install.sh
        rm -f /tmp/zoxide-install.sh
    fi
else
    pkg_ensure zoxide
fi

# =========================
# ZSH PLUGINS
# =========================
ZSH_PLUGIN_DIR="$HOME/.zsh"
mkdir -p "$ZSH_PLUGIN_DIR"

clone_if_not_exists() {
    local repo=$1
    local dest=$2

    if [ ! -d "$dest" ]; then
        git clone "$repo" "$dest"
    fi
}

clone_if_not_exists https://github.com/zsh-users/zsh-autosuggestions "$ZSH_PLUGIN_DIR/zsh-autosuggestions"
clone_if_not_exists https://github.com/zsh-users/zsh-syntax-highlighting "$ZSH_PLUGIN_DIR/zsh-syntax-highlighting"

# =========================
# DOTFILES LINK
# =========================
DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
mkdir -p ~/.config


mkdir -p ~/.config/bash

# Bash (fallback + scripts)
safe_link "$DOTFILES_DIR/config/bash/.bashrc" "$HOME/.bashrc"
safe_link "$DOTFILES_DIR/config/bash/.bash_aliases" "$HOME/.bash_aliases"

# Zsh (principal)
safe_link "$DOTFILES_DIR/config/bash/.zshrc" "$HOME/.zshrc"
safe_link "$DOTFILES_DIR/config/bash/prompt.zsh" "$HOME/.config/bash/prompt.zsh"

# =========================
# SHELL PAR DÉFAUT
# =========================
if command -v zsh &> /dev/null; then
    if [[ "$SHELL" != *"zsh" ]]; then
        info "Switching default shell to zsh..."
        chsh -s "$(which zsh)"
    fi
fi

ok "Shell environment configured successfully."
