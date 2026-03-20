#!/usr/bin/env bash
set -e

echo "-------------------------------------------------------"
echo "  Installation Hyprland + Moteur Caelestia (Fedora)    "
echo "-------------------------------------------------------"

# --- 1. Variables de chemins ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
CAELESTIA_SRC="$DOTFILES_DIR/caelestia-fedora"
CONF_DEST="$HOME/.config"

# --- 2. Dépendances de Caelestia ---
echo "[INFO] Installation des dépendances système..."
sudo dnf copr enable -y errornointernet/quickshell
sudo dnf copr enable -y aneagle/ags-3

# Dépendances de compilation et runtime
PKGS=(
    hyprland xdg-desktop-portal-hyprland waybar wofi foot fzf zoxide
    quickshell-git python3-pip python3-build aubio-devel pipewire-devel 
    gcc-c++ ImageMagick materialyoucolor-python
)
sudo dnf install -y "${PKGS[@]}"

# --- 3. Fonctions utilitaires ---
safe_link() {
    local src=$1
    local dest=$2
    mkdir -p "$(dirname "$dest")"
    [ -L "$dest" ] || [ -f "$dest" ] && rm -rf "$dest"
    ln -s "$src" "$dest"
    echo "[OK] Linked: $dest"
}

# --- 4. Installation du moteur Caelestia ---
install_caelestia_engine() {
    echo "[INFO] Installation du CLI Caelestia..."
    # Installation propre du CLI (nécessaire pour les couleurs dynamiques)
    if [ -d "$CAELESTIA_SRC" ]; then
        # Installation du shell dans Quickshell
        safe_link "$CAELESTIA_SRC/shell" "$CONF_DEST/quickshell/caelestia"
        
        # Compilation du beat-detector (C++)
        echo "[INFO] Compilation du beat-detector..."
        BUILD_DIR="/tmp/caelestia_build"
        mkdir -p "$BUILD_DIR"
        g++ -std=c++17 -O2 \
            $(pkg-config --cflags --libs aubio libpipewire-0.3) \
            "$CAELESTIA_SRC/shell/assets/cpp/beat-detector.cpp" \
            -o "$BUILD_DIR/beat_detector"
        
        sudo mkdir -p /usr/local/lib/caelestia/
        sudo cp "$BUILD_DIR/beat_detector" /usr/local/lib/caelestia/
    fi
}

# --- 5. Déploiement des configurations ---

# Vos configs personnelles (prioritaires)
echo "[INFO] Déploiement de vos configurations personnelles..."
safe_link "$DOTFILES_DIR/config/hyprland/hyprland.conf" "$CONF_DEST/hypr/hyprland.conf"
safe_link "$DOTFILES_DIR/config/hyprland/waybar"       "$CONF_DEST/waybar"
safe_link "$DOTFILES_DIR/config/hyprland/wofi"         "$CONF_DEST/wofi"
safe_link "$DOTFILES_DIR/config/hyprland/foot/foot.ini" "$CONF_DEST/foot/foot.ini"
safe_link "$DOTFILES_DIR/config/bash/starship.toml"    "$CONF_DEST/starship.toml"

# Assets de Caelestia (pour les importer dans votre config)
echo "[INFO] Intégration des assets Caelestia..."
safe_link "$CAELESTIA_SRC/hypr/scheme"   "$CONF_DEST/hypr/caelestia/scheme"
safe_link "$CAELESTIA_SRC/hypr/scripts"  "$CONF_DEST/hypr/caelestia/scripts"
safe_link "$CAELESTIA_SRC/hypr/hyprland" "$CONF_DEST/hypr/caelestia/core"

# Thèmes QT Caelestia
safe_link "$CAELESTIA_SRC/qt5ct" "$CONF_DEST/qt5ct"
safe_link "$CAELESTIA_SRC/qt6ct" "$CONF_DEST/qt6ct"

# --- 6. Exécution ---
install_caelestia_engine

echo "-------------------------------------------------------"
echo "  TERMINE ! Pensez à ajouter les 'source' dans votre   "
echo "  hyprland.conf pour utiliser les couleurs Caelestia.  "
echo "-------------------------------------------------------"