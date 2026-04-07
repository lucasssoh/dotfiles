#!/usr/bin/env bash

# Exit immediately if a command exits with a non-zero status
set -e

# Colors and formatting
BOLD="\e[1m"
GREEN="\e[32m"
YELLOW="\e[33m"
RED="\e[31m"
BLUE="\e[34m"
RESET="\e[0m"

# Display functions (Now in English)
info()    { echo -e "${BLUE}[INFO]${RESET}  $*"; }
ok()      { echo -e "${GREEN}[ OK ]${RESET}  $*"; }
warn()    { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
err()     { echo -e "${RED}[ ERR]${RESET}  $*"; exit 1; }
section() { echo -e "\n${BOLD}── $* ──${RESET}\n"; }

# Repo root directory
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ============================================================
# BEFORE STARTING
# ============================================================
section "LOGIN MANAGER INSTALLATION (GREETD + TUIGREET)"

warn "This script will modify system-wide login manager configuration."
read -rp "Continue? [y/N]: " CONFIRM
[[ "$CONFIRM" =~ ^[Yy]$ ]] || err "Installation aborted."

# ============================================================
# DISTRO DETECTION & PACKAGE INSTALLATION
# ============================================================
section "Package Installation"

if command -v dnf &>/dev/null; then
    info "Fedora detected. Enabling COPR repository for tuigreet..."
    sudo dnf copr enable -y pennbauman/ports
    sudo dnf install -y greetd greetd-tuigreet
elif command -v pacman &>/dev/null; then
    info "Arch Linux detected."
    sudo pacman -S --noconfirm --needed greetd greetd-tuigreet
else
    err "Unsupported distribution for automatic tuigreet installation."
fi

# ============================================================
# GREETER USER SETUP
# ============================================================
section "Greeter User Configuration"

if ! id "greeter" &>/dev/null; then
    info "Creating system user 'greeter'..."
    sudo useradd -r -M -G video,render -s /sbin/nologin greeter
    ok "User 'greeter' created."
else
    info "Updating 'greeter' user groups..."
    sudo usermod -aG video,render greeter
    ok "User groups updated."
fi

# ============================================================
# FILE DEPLOYMENT
# ============================================================
section "Configuration Deployment"

# 1. Create directory for custom ASCII art
sudo mkdir -p /usr/local/share/login-manager/

# 2. Backup old config if it exists
if [ -f /etc/greetd/config.toml ]; then
    sudo cp /etc/greetd/config.toml /etc/greetd/config.toml.bak
    info "Backup of /etc/greetd/config.toml created."
fi

# 3. Install files from repo to system
info "Installing files..."
sudo install -Dm644 "$REPO_DIR/greetd/config.toml" /etc/greetd/config.toml
sudo install -Dm755 "$REPO_DIR/scripts/greetd-wrapper.sh" /usr/local/bin/greetd-wrapper
sudo install -Dm644 "$REPO_DIR/assets/ascii.txt" /usr/local/share/login-manager/ascii.txt

# 4. Set permissions (critical for greeter user access)
sudo chown greeter:greeter /usr/local/share/login-manager/ascii.txt
sudo chmod 644 /usr/local/share/login-manager/ascii.txt

ok "Files installed successfully."

# ============================================================
# SERVICE MANAGEMENT
# ============================================================
section "Enabling Service"

# Disable common display managers
for dm in gdm sddm lightdm; do
    if systemctl is-enabled "$dm" &>/dev/null; then
        sudo systemctl disable "$dm"
        warn "Service $dm disabled."
    fi
done

# Enable and start greetd
sudo systemctl enable greetd
ok "greetd is now enabled."

# ============================================================
# FINAL NOTE
# ============================================================
echo -e "\n${GREEN}${BOLD}✅ INSTALLATION COMPLETE${RESET}"
echo "-------------------------------------------------------"
echo "Important Notes:"
echo "1. Reboot to apply changes."
echo "2. Inside tuigreet, use F2 to select your session."
echo "3. If something goes wrong (black screen):"
echo "   Press Ctrl+Alt+F2 to login and disable greetd."
echo "-------------------------------------------------------"
