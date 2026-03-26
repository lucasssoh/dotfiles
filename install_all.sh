#!/usr/bin/env bash
set -e

# -----------------------------
# Détection du gestionnaire de paquets
# -----------------------------
if command -v dnf &> /dev/null; then
    PKGMGR="sudo dnf install -y"
elif command -v pacman &> /dev/null; then
    PKGMGR="sudo pacman -S --noconfirm"
elif command -v apt-get &> /dev/null; then
    PKGMGR="sudo apt-get install -y"
else
    echo "[ERREUR] Gestionnaire de paquets non supporté."
    exit 1
fi

# -----------------------------
# Installer les bases
# -----------------------------
echo "[INFO] Installation des bases (git, curl, ImageMagick)..."
$PKGMGR git curl ImageMagick

# -----------------------------
# Installer pip
# -----------------------------
echo "[INFO] Installation de pip..."
if command -v python3 &> /dev/null; then
    if command -v dnf &> /dev/null; then
        # Sur Fedora, on prend aussi python3-devel pour plus de sécurité avec pip
        sudo dnf install -y python3-pip python3-devel
    elif command -v pacman &> /dev/null; then
        sudo pacman -S --noconfirm python-pip
    elif command -v apt-get &> /dev/null; then
        sudo apt-get install -y python3-pip python3-dev
    fi
else
    echo "[WARN] Python3 n'est pas installé, pip ignoré."
fi

# -----------------------------
# Définir le dossier racine
# -----------------------------
DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# -----------------------------
# Lancer chaque module
# -----------------------------
MODULES=(fonts bash tmux wezterm nvim)
HYPR_MODULE="hyprland"

for module in "${MODULES[@]}"; do
    MODULE_PATH="$DOTFILES_DIR/config/$module"
    if [ -d "$MODULE_PATH" ]; then
        echo "[INFO] Lancement du module : $module"
        chmod +x "$MODULE_PATH/install.sh"
        "$MODULE_PATH/install.sh"
    fi
done

# -----------------------------
# Installer Hyprland en dernier
# -----------------------------
HYPR_PATH="$DOTFILES_DIR/config/$HYPR_MODULE"
if [ -d "$HYPR_PATH" ]; then
    echo "[INFO] Lancement du module Hyprland"
    chmod +x "$HYPR_PATH/install.sh"
    "$HYPR_PATH/install.sh"
fi

# -----------------------------
# Terminé
# -----------------------------
echo "[OK] Installation globale terminée."
