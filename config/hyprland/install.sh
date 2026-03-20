#!/usr/bin/env bash
set -e

echo "[INFO] Installation minimale pour Caelestia (Fish + npm + sass)"

# --- Détection du gestionnaire de paquets ---
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

# --- Installer Fish, npm ---
echo "[INFO] Installation de Fish, npm..."
$PKG fish npm

# --- Installer Sass via npm si présent ---
if command -v npm &> /dev/null; then
    echo "[INFO] Installation de Sass via npm..."
    sudo npm install -g sass
fi

# --- Lancer le script fish ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/install.fish" ]; then
    echo "[INFO] Lancement de install.fish..."
    fish "$SCRIPT_DIR/install.fish"
else
    echo "[ERREUR] install.fish introuvable !"
    exit 1
fi

echo "[OK] Installation Hyprland/Caelestia terminée (via Fish)"