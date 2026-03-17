#!/bin/bash

# 1. Détection du gestionnaire de paquets
if command -v dnf &> /dev/null; then
    INSTALL="sudo dnf install -y"
elif command -v pacman &> /dev/null; then
    INSTALL="sudo pacman -S --noconfirm"
elif command -v apt-get &> /dev/null; then
    INSTALL="sudo apt-get install -y"
fi

echo "[INFO] Installation des outils shell (fzf, zoxide)..."
$INSTALL fzf zoxide

# 2. Installation de Starship
if ! command -v starship &> /dev/null; then
    echo "[INFO] Installation de Starship..."
    curl -sS https://starship.rs/install.sh | sh -s -- -y
fi

# --- 3. Liens symboliques ---
MODULE_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

echo "[INFO] Configuration des liens depuis : $MODULE_DIR"

mkdir -p ~/.config

# Fonction de nettoyage pour éviter les liens circulaires ou foireux
safe_link() {
    local src=$1
    local dest=$2
    # Si la destination existe (fichier ou lien), on dégage
    [ -L "$dest" ] || [ -f "$dest" ] && rm -rf "$dest"
    ln -s "$src" "$dest"
}

# Application sécurisée
safe_link "$MODULE_DIR/.bashrc" ~/.bashrc
safe_link "$MODULE_DIR/.bash_aliases" ~/.bash_aliases
safe_link "$MODULE_DIR/starship.toml" ~/.config/starship.toml

echo "[OK] Bash et Starship sont configurés."
