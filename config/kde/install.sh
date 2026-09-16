#!/usr/bin/env bash
# ============================================================
# INSTALL.SH — Minimal KDE Plasma 6 setup
# Optimized for Fedora
# ============================================================

set -Eeuo pipefail

# Package helper: queries before it installs, so an already-provisioned
# machine performs zero package-manager calls and never prompts for sudo.
. "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../../scripts/lib/pkg.sh"

BOLD="\e[1m"
GREEN="\e[32m"
BLUE="\e[34m"
RESET="\e[0m"

info() { echo -e "${BLUE}[INFO]${RESET}  $*"; }
ok()   { echo -e "${GREEN}[ OK ]${RESET}  $*"; }
section() { echo -e "\n${BOLD}── $* ──${RESET}\n"; }

# ============================================================
# MINIMAL PACKAGES (Plasma 6)
# ============================================================
section "Installing Minimal KDE Plasma"

PKGS=(
    # Core Desktop
    plasma-desktop kscreen kinfocenter systemsettings
    # Essential system utilities
    plasma-nm plasma-pa plasma-systemmonitor bluedevil
    power-profiles-daemon kde-gtk-config breeze-gtk
    kscreenlocker xdg-desktop-portal-kde
    # Theming & effects
    kvantum qt5-qtstyleplugins qt6-qtstyleplugins
    # Base fonts (in case your fonts module didn't install them)
    google-noto-sans-fonts google-noto-emoji-fonts
)

# --allowerasing is why this one does not go through pkg_ensure: the KDE set
# deliberately replaces conflicting packages, which is a decision pkg_ensure
# must never make on its own. It is still gated on there being something
# missing, so a provisioned machine skips it entirely.
kde_missing=()
for p in "${PKGS[@]}"; do pkg_installed "$p" || kde_missing+=("$p"); done
if [ "${#kde_missing[@]}" -gt 0 ]; then
    info "KDE: installing ${#kde_missing[@]} missing package(s)…"
    sudo_maybe dnf install -y "${kde_missing[@]}" --allowerasing
else
    info "KDE: all packages already present."
fi
ok "KDE Minimal packages installed."

# ============================================================
# THEMES & ICONS (Reversal)
# ============================================================
section "Installing Reversal Icons & Orchis Theme"

TEMP_DIR="/tmp/kde_setup"
# Clean slate: a prior run that failed partway through (e.g. after `git
# clone` but before the target dir below existed) would otherwise leave a
# non-empty $TEMP_DIR that makes every subsequent `git clone` fail forever.
rm -rf "$TEMP_DIR"
mkdir -p "$TEMP_DIR"

# Reversal Icons
if [ ! -d "$HOME/.local/share/icons/Reversal" ]; then
    info "Downloading Reversal Icons..."
    git clone https://github.com/vinceliuice/reversal-icon-theme.git "$TEMP_DIR/reversal"
    bash "$TEMP_DIR/reversal/install.sh" -a
    ok "Reversal icons installed."
fi

# Orchis Theme (for Plasma and Kvantum)
if [ ! -d "$HOME/.local/share/aurorae/themes/Orchis" ]; then
    info "Downloading Orchis Theme..."
    git clone https://github.com/vinceliuice/Orchis-kde.git "$TEMP_DIR/orchis"
    bash "$TEMP_DIR/orchis/install.sh"
    ok "Orchis theme installed."
fi

# ============================================================
# AUTOMATIC CONFIGURATION
# ============================================================
section "Applying minimal config"

# Apply the color scheme and icons via CLI
plasma-apply-colorscheme OrchisDark || true

info "Setting Reversal-dark icons..."
/usr/bin/kwriteconfig6 --file kdeglobals --group Icons --key Theme Reversal-dark

ok "KDE Setup complete."
echo -e "\n${BOLD}To start KDE from the TTY:${RESET}"
echo "dbus-run-session startplasma-wayland"
