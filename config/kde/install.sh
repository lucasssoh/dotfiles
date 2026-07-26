#!/usr/bin/env bash
# ============================================================
# INSTALL.SH — Minimal KDE Plasma 6 setup
# Optimized for Fedora
# ============================================================

set -e

BOLD="\e[1m"
GREEN="\e[32m"
BLUE="\e[34m"
RESET="\e[0m"

info() { echo -e "${BLUE}[INFO]${RESET}  $*"; }
ok()   { echo -e "${GREEN}[ OK ]${RESET}  $*"; }
section() { echo -e "\n${BOLD}── $* ──${RESET}\n"; }

# ============================================================
# PACKAGES MINIMAUX (Plasma 6)
# ============================================================
section "Installing Minimal KDE Plasma"

PKGS=(
    # Core Desktop
    plasma-desktop kscreen kinfocenter systemsettings
    # Utilitaires système essentiels
    plasma-nm plasma-pa plasma-systemmonitor bluedevil 
    power-profiles-daemon kde-gtk-config breeze-gtk 
    kscreenlocker xdg-desktop-portal-kde
    # Thémage & Effets
    kvantum qt5-qtstyleplugins qt6-qtstyleplugins
    # Fonts de base (si non installées par ton module fonts)
    google-noto-sans-fonts google-noto-emoji-fonts
)

sudo dnf install -y "${PKGS[@]}" --allowerasing
ok "KDE Minimal packages installed."

# ============================================================
# THEMES & ICONS (Reversal)
# ============================================================
section "Installing Reversal Icons & Orchis Theme"

TEMP_DIR="/tmp/kde_setup"
mkdir -p $TEMP_DIR

# Reversal Icons
if [ ! -d "$HOME/.local/share/icons/Reversal" ]; then
    info "Downloading Reversal Icons..."
    git clone https://github.com/vinceliuice/reversal-icon-theme.git $TEMP_DIR/reversal
    bash $TEMP_DIR/reversal/install.sh -a
    ok "Reversal icons installed."
fi

# Orchis Theme (Pour Plasma et Kvantum)
if [ ! -d "$HOME/.local/share/aurorae/themes/Orchis" ]; then
    info "Downloading Orchis Theme..."
    git clone https://github.com/vinceliuice/Orchis-kde.git $TEMP_DIR/orchis
    bash $TEMP_DIR/orchis/install.sh
    ok "Orchis theme installed."
fi

# ============================================================
# CONFIGURATION AUTOMATIQUE
# ============================================================
section "Applying minimal config"

# Appliquer le thème de couleur et les icônes via CLI
plasma-apply-colorscheme OrchisDark || true
plasma-apply-cursortheme Bibata-Modern-Classic || true # Optionnel si tu les as

info "Setting Reversal-dark icons..."
/usr/bin/kwriteconfig6 --file kdeglobals --group Icons --key Theme Reversal-dark

ok "KDE Setup complete."
echo -e "\n${BOLD}To start KDE from the TTY:${RESET}"
echo "dbus-run-session startplasma-wayland"
