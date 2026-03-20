#!/usr/bin/env bash
set -e

echo "-------------------------------------------------------"
echo "  Installation Hyprland + Moteur Caelestia (Fedora)    "
echo "-------------------------------------------------------"

# --- 1. Variables de chemins ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# On remonte de config/hyprland/ vers la racine des dotfiles
DOTFILES_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
CAELESTIA_SRC="$DOTFILES_DIR/caelestia-fedora"
CONF_DEST="$HOME/.config"

# --- 2. Dépendances de Caelestia ---
echo "[INFO] Installation des dépendances système..."
sudo dnf copr enable -y errornointernet/quickshell
sudo dnf copr enable -y aneagle/ags-3

# PKGS nettoyé (materialyoucolor-python retiré car c'est un paquet pip)
PKGS=(
    hyprland xdg-desktop-portal-hyprland waybar wofi foot fzf zoxide
    quickshell-git python3-pip python3-build aubio-devel pipewire-devel 
    gcc-c++ ImageMagick brightnessctl
)
sudo dnf install -y "${PKGS[@]}"

# --- 3. Fonctions utilitaires ---
safe_link() {
    local src=$1
    local dest=$2
    if [ ! -e "$src" ]; then
        echo "[SKIP] Source introuvable : $src"
        return
    fi
    # Si le destinataire est un dossier réel (pas un lien), on le dégage pour mettre le lien
    if [ -d "$dest" ] && [ ! -L "$dest" ]; then
        rm -rf "$dest"
    fi
    mkdir -p "$(dirname "$dest")"
    [ -L "$dest" ] || [ -f "$dest" ] && rm -rf "$dest"
    ln -s "$src" "$dest"
    echo "[OK] Linked: $dest"
}

# --- 4. Installation du moteur Caelestia ---
install_caelestia_engine() {
    echo "[INFO] Installation du moteur Python (Material You)..."
    # Installation via pip car absent des dépôts DNF
    sudo python3 -m pip install materialyoucolor --break-system-packages

    if [ -d "$CAELESTIA_SRC" ]; then
        # On vérifie si le dossier shell existe dans ton clone
        if [ -d "$CAELESTIA_SRC/shell" ]; then
            echo "[INFO] Configuration du Shell Caelestia..."
            safe_link "$CAELESTIA_SRC/shell" "$CONF_DEST/quickshell/caelestia"
            
            # Compilation du beat-detector si les sources sont présentes
            if [ -f "$CAELESTIA_SRC/shell/assets/cpp/beat-detector.cpp" ]; then
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
        fi
    fi
}

# --- 5. Déploiement des configurations ---

echo "[INFO] Déploiement de vos configurations personnelles..."
# Correction du chemin vers ton hyprland.conf (basé sur ta structure ls)
safe_link "$DOTFILES_DIR/config/hyprland/hyprland.conf" "$CONF_DEST/hypr/hyprland.conf"
safe_link "$DOTFILES_DIR/config/hyprland/waybar"       "$CONF_DEST/waybar"
safe_link "$DOTFILES_DIR/config/hyprland/wofi"         "$CONF_DEST/wofi"
safe_link "$DOTFILES_DIR/config/hyprland/foot/foot.ini" "$CONF_DEST/foot/foot.ini"

# Note : Ton ls montre config/bash/starship.toml
safe_link "$DOTFILES_DIR/config/bash/starship.toml"    "$CONF_DEST/starship.toml"

echo "[INFO] Intégration des assets Caelestia..."
# On lie les dossiers de ressources pour pouvoir les 'source' dans hyprland.conf
safe_link "$CAELESTIA_SRC/hypr/scheme"   "$CONF_DEST/hypr/caelestia/scheme"
safe_link "$CAELESTIA_SRC/hypr/scripts"  "$CONF_DEST/hypr/caelestia/scripts"
safe_link "$CAELESTIA_SRC/hypr/hyprland" "$CONF_DEST/hypr/caelestia/core"

# Thèmes QT (pour l'harmonie des couleurs)
safe_link "$CAELESTIA_SRC/qt5ct" "$CONF_DEST/qt5ct"
safe_link "$CAELESTIA_SRC/qt6ct" "$CONF_DEST/qt6ct"

# --- 6. Exécution ---
install_caelestia_engine

echo "-------------------------------------------------------"
echo "  TERMINE ! L'erreur DNF est résolue.                  "
echo "  Pensez à utiliser 'caelestia color' pour générer     "
echo "  votre premier thème.                                 "
echo "-------------------------------------------------------"