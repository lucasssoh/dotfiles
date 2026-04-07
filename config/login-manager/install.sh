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

# Display functions
info()    { echo -e "${BLUE}[INFO]${RESET}  $*"; }
ok()      { echo -e "${GREEN}[ OK ]${RESET}  $*"; }
warn()    { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
err()     { echo -e "${RED}[ ERR]${RESET}  $*"; exit 1; }
section() { echo -e "\n${BOLD}── $* ──${RESET}\n"; }

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

section "LOGIN MANAGER INSTALLATION (GREETD + TUIGREET)"

warn "This script will modify system-wide login manager configuration."
read -rp "Continue? [y/N]: " CONFIRM
[[ "$CONFIRM" =~ ^[Yy]$ ]] || err "Installation aborted."

# ============================================================
# PACKAGE INSTALLATION
# ============================================================
section "Package Installation"

if command -v dnf &>/dev/null; then
    info "Fedora detected. Enabling COPR for tuigreet..."
    sudo dnf copr enable -y pennbauman/ports
    sudo dnf install -y greetd greetd-tuigreet
elif command -v pacman &>/dev/null; then
    sudo pacman -S --noconfirm --needed greetd greetd-tuigreet
fi

# ============================================================
# USER SETUP
# ============================================================
section "Greeter User Configuration"

if ! id "greeter" &>/dev/null; then
    sudo useradd -r -M -G video,render -s /sbin/nologin greeter
    ok "User 'greeter' created."
else
    sudo usermod -aG video,render greeter
    ok "User groups updated."
fi

# ============================================================
# ASCII ART TO /ETC/ISSUE (The Fix)
# ============================================================
section "Deploying ASCII Art"

if [ -f "$REPO_DIR/assets/ascii.txt" ]; then
    # We copy your ASCII to /etc/issue so tuigreet can read it natively
    sudo cp "$REPO_DIR/assets/ascii.txt" /etc/issue
    ok "ASCII art deployed to /etc/issue"
else
    err "assets/ascii.txt not found!"
fi

# ============================================================
# CONFIG DEPLOYMENT
# ============================================================
section "Configuration Deployment"

sudo install -Dm644 "$REPO_DIR/greetd/config.toml" /etc/greetd/config.toml
sudo install -Dm755 "$REPO_DIR/scripts/greetd-wrapper.sh" /usr/local/bin/greetd-wrapper

# Create cache directory for --remember features
sudo mkdir -p /var/cache/tuigreet
sudo chown greeter:greeter /var/cache/tuigreet
sudo chmod 0755 /var/cache/tuigreet

ok "Configuration and wrapper installed."

# ============================================================
# SERVICE MANAGEMENT
# ============================================================
section "Enabling Service"

for dm in gdm sddm lightdm; do
    sudo systemctl disable "$dm" &>/dev/null || true
done

sudo systemctl enable greetd
ok "greetd is now enabled."

echo -e "\n${GREEN}${BOLD}✅ INSTALLATION COMPLETE${RESET}\n"
