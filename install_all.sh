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
echo "[INFO] Installation des bases (git, curl)..."
$PKGMGR git curl

echo "[INFO] Installation de pip..."
if command -v python3 &> /dev/null; then
    if command -v dnf &> /dev/null; then
        sudo dnf install -y python3-pip
    elif command -v pacman &> /dev/null; then
        sudo pacman -S --noconfirm python-pip
    elif command -v apt-get &> /dev/null; then
        sudo apt-get install -y python3-pip
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
MODULES=(fonts bash wezterm nvim)
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
# Thème Visuel (Pywal & Wallpaper)
# -----------------------------
echo "[INFO] Configuration du thème visuel..."

# 1. Installer Pywal via pip (si pas déjà fait)
if ! command -v wal &> /dev/null; then
    pip install pywal --user
fi

# 2. S'assurer que le dossier des fonds d'écran existe dans tes dotfiles
WALLPAPER_DIR="$DOTFILES_DIR/config/hyprland/wallpapers"
if [ -d "$WALLPAPER_DIR" ]; then
    # On prend le premier wallpaper trouvé pour initialiser le thème
    FIRST_WALL=$(find "$WALLPAPER_DIR" -type f \( -name "*.jpg" -o -name "*.png" \) | head -n 1)
    
    if [ -n "$FIRST_WALL" ]; then
        echo "[INFO] Application du thème basé sur : $(basename "$FIRST_WALL")"
        # On utilise le PATH local au cas où le shell n'est pas encore rechargé
        "$HOME/.local/bin/wal" -i "$FIRST_WALL"
    fi
else
    echo "[WARN] Dossier wallpapers introuvable dans $WALLPAPER_DIR"
fi
# -----------------------------
# Terminé
# -----------------------------
echo "[OK] Installation globale terminée."