#!/usr/bin/env bash
set -e
echo "[INFO] Installation complète de Hyprland et accessoires (multi-distro)..."

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

$PKG_INSTALL hyprland xdg-desktop-portal-hyprland hyprpaper
$PKG_INSTALL waybar wofi foot fzf zoxide

mkdir -p ~/.config/hypr
mkdir -p ~/.config/hypr/scripts
mkdir -p ~/.config/waybar
mkdir -p ~/.config/wofi
mkdir -p ~/.config/foot

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

safe_link() {
    local src=$1
    local dest=$2
    if [ -L "$dest" ] || [ -f "$dest" ]; then
        rm -rf "$dest"
    fi
    ln -s "$src" "$dest"
}

# Hyprland
safe_link "$DOTFILES_DIR/config/hyprland/hyprland.conf" ~/.config/hypr/hyprland.conf

# Script popup waybar
cp "$DOTFILES_DIR/config/hyprland/scripts/popup.sh" ~/.config/hypr/scripts/popup.sh
chmod +x ~/.config/hypr/scripts/popup.sh

# Wallpaper
WALL_DIR="$HOME/Pictures/Wallpapers"
mkdir -p "$WALL_DIR"
WALL_SRC="$DOTFILES_DIR/config/hyprland/wallpapers/pepper-carrot.jpg"
WALL_DEST="$WALL_DIR/pepper-carrot.jpg"
if [ -f "$WALL_SRC" ]; then
    safe_link "$WALL_SRC" "$WALL_DEST"
    cat <<EOF > ~/.config/hypr/hyprpaper.conf
preload = $WALL_DEST
wallpaper = ,$WALL_DEST
splash = false
EOF
    echo "[INFO] Wallpaper et config hyprpaper générés."
fi

# Waybar
safe_link "$DOTFILES_DIR/config/hyprland/waybar/config" ~/.config/waybar/config
safe_link "$DOTFILES_DIR/config/hyprland/waybar/style.css" ~/.config/waybar/style.css

# Wofi
safe_link "$DOTFILES_DIR/config/hyprland/wofi/theme.rasi" ~/.config/wofi/theme.rasi

# Foot
safe_link "$DOTFILES_DIR/config/hyprland/foot/foot.ini" ~/.config/foot/foot.ini

echo "[OK] Hyprland et tous ses accessoires sont installés et configurés."