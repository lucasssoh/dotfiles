#!/usr/bin/env bash
set -e

echo "[INFO] Installation complète de Hyprland et accessoires (multi-distro)..."

# Détection du gestionnaire de paquets
if command -v dnf &> /dev/null; then
    PKG_INSTALL="sudo dnf install -y"
elif command -v pacman &> /dev/null; then
    PKG_INSTALL="sudo pacman -S --noconfirm"
elif command -v apt-get &> /dev/null; then
    PKG_INSTALL="sudo apt-get install -y"
else
    echo "[ERREUR] Gestionnaire de paquets non supporté."
    exit 1
fi

# ------------------------
# Installer Hyprland minimal et hyprpaper
# ------------------------
$PKG_INSTALL hyprland xdg-desktop-portal-hyprland hyprpaper

# Installer les accessoires
$PKG_INSTALL waybar wofi foot starship fzf zoxide

# ------------------------
# Créer dossiers de config
# ------------------------
mkdir -p ~/.config/hypr
mkdir -p ~/.config/waybar
mkdir -p ~/.config/wofi
mkdir -p ~/.config/foot

# Racine du repo
DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# ------------------------
# Fonction safe_link
# ------------------------
safe_link() {
    local src=$1
    local dest=$2
    if [ -L "$dest" ] || [ -f "$dest" ]; then
        rm -rf "$dest"
    fi
    ln -s "$src" "$dest"
}

# ------------------------
# Lier configs principales
# ------------------------
# Hyprland
safe_link "$DOTFILES_DIR/config/hyprland/hyprland.conf" ~/.config/hypr/hyprland.conf

# Wallpaper
WALL_DIR="$HOME/Pictures/Wallpapers"
mkdir -p "$WALL_DIR"
WALL_SRC="$DOTFILES_DIR/config/hyprland/wallpapers/pepper-carrot.jpg"
if [ -f "$WALL_SRC" ]; then
    safe_link "$WALL_SRC" "$WALL_DIR/pepper-carrot.jpg"
    echo "[INFO] Wallpaper ajouté : $WALL_DIR/pepper-carrot.jpg"
fi

# Waybar
safe_link "$DOTFILES_DIR/config/hyprland/waybar/config" ~/.config/waybar/config
safe_link "$DOTFILES_DIR/config/hyprland/waybar/style.css" ~/.config/waybar/style.css

# Wofi
safe_link "$DOTFILES_DIR/config/hyprland/wofi/theme.rasi" ~/.config/wofi/theme.rasi

# Foot
safe_link "$DOTFILES_DIR/config/hyprland/foot/foot.ini" ~/.config/foot/foot.ini

# ------------------------
# Message final
# ------------------------
echo "[OK] Hyprland et tous ses accessoires sont installés et configurés."