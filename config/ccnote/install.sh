#!/usr/bin/env bash
set -e

BLUE="\e[34m"
GREEN="\e[32m"
RESET="\e[0m"

info() { echo -e "${BLUE}[INFO]${RESET}  $*"; }
ok()   { echo -e "${GREEN}[ OK ]${RESET}  $*"; }

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DEST_DIR="$HOME/.config/ccnote"

info "Setting up the ccnote workflow..."

# 1. Création du dossier de destination dans ~/.config
mkdir -p "$DEST_DIR"

# Fonction pour lier proprement
safe_link() {
    local src=$1
    local dest=$2
    if [ -L "$dest" ] || [ -f "$dest" ]; then
        rm -rf "$dest"
    fi
    ln -s "$src" "$dest"
}

# 2. Liens symboliques du script Python et de la config Zsh
safe_link "$DOTFILES_DIR/config/ccnote/ccnote.py" "$DEST_DIR/ccnote.py"
safe_link "$DOTFILES_DIR/config/ccnote/ccnote.zsh" "$DEST_DIR/ccnote.zsh"

# Rendre le script Python exécutable à sa source
chmod +x "$DOTFILES_DIR/config/ccnote/ccnote.py"

ok "ccnote module installed to $DEST_DIR"
echo ""
echo "To enable the command, add this line at the end of your ~/.zshrc or shell startup file:"
echo "   source ~/.config/ccnote/ccnote.zsh"
