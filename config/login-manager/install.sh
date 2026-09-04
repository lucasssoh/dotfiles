#!/usr/bin/env bash

# Exit immediately if a command exits with a non-zero status
set -Eeuo pipefail

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
# NO BANNER: undo any leftover ASCII-art deployment from an older
# install (restore-issue.service, its unit file, and the /etc/issue
# it wrote), so /etc/issue goes back to its package-managed symlink.
# ============================================================
section "Cleaning Up Old Banner Setup"

sudo systemctl disable --now restore-issue.service &>/dev/null || true
sudo rm -f /etc/systemd/system/restore-issue.service
sudo rm -f /usr/local/share/tuigreet/issue.txt
if [ ! -L /etc/issue ]; then
    sudo rm -f /etc/issue
    sudo ln -s ../usr/lib/issue /etc/issue
fi
sudo systemctl daemon-reload
ok "No banner: /etc/issue restored to its default symlink."

# ============================================================
# CONFIG DEPLOYMENT
# ============================================================
section "Configuration Deployment"

sudo install -Dm644 "$REPO_DIR/greetd/config.toml" /etc/greetd/config.toml

# Create cache directory for --remember features
sudo mkdir -p /var/cache/tuigreet
sudo chown greeter:greeter /var/cache/tuigreet
sudo chmod 0755 /var/cache/tuigreet

ok "Configuration installed."

# ============================================================
# SERVICE MANAGEMENT
# ============================================================
section "Enabling Service"

for dm in gdm sddm lightdm; do
    sudo systemctl disable "$dm" &>/dev/null || true
done

sudo systemctl enable greetd
ok "greetd is now enabled."

echo -e "\n${GREEN}${BOLD}INSTALLATION COMPLETE${RESET}\n"
