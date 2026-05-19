#!/usr/bin/env bash
set -e

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DEST_DIR="$HOME/.config/ccnote"

echo "[INFO] Configuration du workflow ccnote..."

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

echo "[OK] Module ccnote installé dans $DEST_DIR"
echo ""
echo "Pour activer la commande, ajoute cette ligne à la fin de ton ~/.zshrc ou fichier de démarrage shell :"
echo "   source ~/.config/ccnote/ccnote.zsh"
