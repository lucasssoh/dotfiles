#!/usr/bin/env bash
set -Eeuo pipefail

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
# Compact status + persistent log (terminal = summary, log = full detail)
# -----------------------------
source "$DOTFILES_DIR/scripts/lib/status.sh"
status_init
sudo -v || true  # prime the sudo cache once up front; modules run long enough for it to expire mid-summary otherwise

# -----------------------------
# Run each module
# -----------------------------
section "Modules"
MODULES=(fonts bash tmux wezterm nvim wireplumber mangohud nemo)
HYPR_MODULE="hyprland"
KDE_MODULE="kde"
#
for module in "${MODULES[@]}"; do
    MODULE_PATH="$DOTFILES_DIR/config/$module"
    if [ -d "$MODULE_PATH" ]; then
        chmod +x "$MODULE_PATH/install.sh"
        run_step "$module" "$MODULE_PATH/install.sh" || true
    else
        skip_step "$module" "directory not found"
    fi
done

# -----------------------------
# Install Hyprland last
# -----------------------------
HYPR_PATH="$DOTFILES_DIR/config/$HYPR_MODULE"
if [ -d "$HYPR_PATH" ]; then
    chmod +x "$HYPR_PATH/install.sh"
    run_step "$HYPR_MODULE" "$HYPR_PATH/install.sh" || true
else
    skip_step "$HYPR_MODULE" "directory not found"
fi

# -----------------------------
# Install KDE Plasma
# -----------------------------
KDE_PATH="$DOTFILES_DIR/config/$KDE_MODULE"
if [ -d "$KDE_PATH" ]; then
    chmod +x "$KDE_PATH/install.sh"
    # The call to kde/install.sh will handle --allowerasing
    run_step "$KDE_MODULE" "$KDE_PATH/install.sh" || true
else
    skip_step "$KDE_MODULE" "directory not found"
fi

# -----------------------------
# Done
# -----------------------------
rc=0
status_summary || rc=$?
exit "$rc"
