#!/usr/bin/env bash
set -e

BOLD="\e[1m"
GREEN="\e[32m"
YELLOW="\e[33m"
RED="\e[31m"
BLUE="\e[34m"
RESET="\e[0m"

info()    { echo -e "${BLUE}[INFO]${RESET}  $*"; }
ok()      { echo -e "${GREEN}[ OK ]${RESET}  $*"; }
warn()    { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
err()     { echo -e "${RED}[ ERR]${RESET}  $*"; exit 1; }
section() { echo -e "\n${BOLD}── $* ──${RESET}\n"; }

# -----------------------------
# Package manager detection
# -----------------------------
if command -v dnf &> /dev/null; then
    PKGMGR="sudo dnf install -y"
elif command -v pacman &> /dev/null; then
    PKGMGR="sudo pacman -S --noconfirm"
elif command -v apt-get &> /dev/null; then
    PKGMGR="sudo apt-get install -y"
else
    err "Unsupported package manager."
fi

# -----------------------------
# Install base packages
# -----------------------------
section "Base packages"
info "Installing base packages (git, curl, ImageMagick)..."
$PKGMGR git curl ImageMagick

# -----------------------------
# Install pip
# -----------------------------
info "Installing pip..."
if command -v python3 &> /dev/null; then
    if command -v dnf &> /dev/null; then
        # On Fedora, also grab python3-devel for extra safety with pip
        sudo dnf install -y python3-pip python3-devel
    elif command -v pacman &> /dev/null; then
        sudo pacman -S --noconfirm python-pip
    elif command -v apt-get &> /dev/null; then
        sudo apt-get install -y python3-pip python3-dev
    fi
else
    warn "Python3 is not installed, skipping pip."
fi

# -----------------------------
# Set the root directory
# -----------------------------
DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# -----------------------------
# Run each module
# -----------------------------
section "Modules"
MODULES=(fonts bash tmux wezterm nvim wireplumber mangohud nemo)
HYPR_MODULE="hyprland"
#
for module in "${MODULES[@]}"; do
    MODULE_PATH="$DOTFILES_DIR/config/$module"
    if [ -d "$MODULE_PATH" ]; then
        info "Running module: $module"
        chmod +x "$MODULE_PATH/install.sh"
        "$MODULE_PATH/install.sh"
    fi
done

# -----------------------------
# Install Hyprland last
# -----------------------------
HYPR_PATH="$DOTFILES_DIR/config/$HYPR_MODULE"
if [ -d "$HYPR_PATH" ]; then
    info "Running Hyprland module..."
    chmod +x "$HYPR_PATH/install.sh"
    "$HYPR_PATH/install.sh"
fi

# -----------------------------
# Install KDE Plasma
# -----------------------------
# Swap HYPR_MODULE for KDE_MODULE
KDE_MODULE="kde"
KDE_PATH="$DOTFILES_DIR/config/$KDE_MODULE"

if [ -d "$KDE_PATH" ]; then
    info "Running KDE Plasma 6 module..."
    chmod +x "$KDE_PATH/install.sh"
    # The call to kde/install.sh will handle --allowerasing
    "$KDE_PATH/install.sh"
else
    warn "KDE module not found at $KDE_PATH"
fi
# -----------------------------
# Done
# -----------------------------
ok "Global installation complete."
