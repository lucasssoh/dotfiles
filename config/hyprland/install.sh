#!/usr/bin/env bash
set -e

echo "[INFO] Installation minimale pour Caelestia (Fish + npm + sass)"

# --- Gestionnaire de paquets ---
if command -v dnf &> /dev/null; then
    PKG="sudo dnf install -y"
elif command -v pacman &> /dev/null; then
    PKG="sudo pacman -S --noconfirm"
elif command -v apt-get &> /dev/null; then
    PKG="sudo apt-get install -y"
else
    echo "[ERREUR] Gestionnaire de paquets non supporté."
    exit 1
fi

# --- Installer Fish et npm ---
echo "[INFO] Installation de Fish, npm..."
$PKG fish npm

# --- Sass via npm ---
if command -v npm &> /dev/null; then
    echo "[INFO] Installation de Sass via npm..."
    sudo npm install -g sass
fi

# --- Lancer install.fish ---
# Corrigé pour pointer vers le bon emplacement
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
INSTALL_FISH="$REPO_ROOT/caelestia-fedora/install.fish"

if [ -f "$INSTALL_FISH" ]; then
    echo "[INFO] Lancement de install.fish..."
    fish "$INSTALL_FISH"
else
    echo "[ERREUR] install.fish introuvable dans $INSTALL_FISH !"
    exit 1
fi

echo "[INFO] Configuration des wallpapers..."

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

bash "$SCRIPT_DIR/set_wallpapers.sh"

