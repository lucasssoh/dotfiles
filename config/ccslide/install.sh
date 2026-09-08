#!/usr/bin/env bash
set -Eeuo pipefail

BLUE="\e[34m"
GREEN="\e[32m"
RESET="\e[0m"

info() { echo -e "${BLUE}[INFO]${RESET}  $*"; }
ok()   { echo -e "${GREEN}[ OK ]${RESET}  $*"; }

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DEST_DIR="$HOME/.config/ccslide"

info "Setting up the ccslide workflow..."

# 1. Create the destination folder under ~/.config
mkdir -p "$DEST_DIR"

# Helper to link cleanly
safe_link() {
    local src=$1
    local dest=$2
    if [ -L "$dest" ] || [ -f "$dest" ]; then
        rm -rf "$dest"
    fi
    ln -s "$src" "$dest"
}

# 2. Symlink the Python script and the Zsh config
safe_link "$DOTFILES_DIR/config/ccslide/ccslide.py"  "$DEST_DIR/ccslide.py"
safe_link "$DOTFILES_DIR/config/ccslide/ccslide.zsh" "$DEST_DIR/ccslide.zsh"

chmod +x "$DOTFILES_DIR/config/ccslide/ccslide.py"

# 3. mdp is the whole point of the module
if ! command -v mdp &> /dev/null; then
    info "mdp introuvable — installe-le avant de présenter (https://github.com/visit1985/mdp)"
fi

ok "ccslide module installed to $DEST_DIR"
echo ""
echo "To enable the command, add this line at the end of your ~/.zshrc or shell startup file:"
echo "   source ~/.config/ccslide/ccslide.zsh"
