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

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ============================================================
# WARNING
# ============================================================
section "WARNING — SYSTEM LOGIN MANAGER"

warn "This will install greetd + agreety as your system login manager."
warn "This affects ALL users."
warn "Incorrect configuration may prevent login."
echo ""

read -rp "Continue? [y/N]: " CONFIRM
[[ "$CONFIRM" =~ ^[Yy]$ ]] || err "Aborted."

# ============================================================
# DISTRO
# ============================================================
section "Detecting distribution"

if command -v dnf &>/dev/null; then
    DISTRO="fedora"
    PKG_INSTALL="sudo dnf install -y"
    PKG_UPDATE="sudo dnf check-update -y || true"
elif command -v pacman &>/dev/null; then
    DISTRO="arch"
    PKG_INSTALL="sudo pacman -S --noconfirm --needed"
    PKG_UPDATE="sudo pacman -Sy"
elif command -v apt-get &>/dev/null; then
    DISTRO="debian"
    PKG_INSTALL="sudo apt-get install -y"
    PKG_UPDATE="sudo apt-get update"
else
    err "Unsupported distro"
fi

# ============================================================
# PACKAGES
# ============================================================
section "Installing greetd + agreety"

$PKG_UPDATE

if [ "$DISTRO" = "fedora" ]; then
    PKGS=(greetd)
elif [ "$DISTRO" = "arch" ]; then
    PKGS=(greetd greetd-agreety)
elif [ "$DISTRO" = "debian" ]; then
    PKGS=(greetd agreety)
fi

$PKG_INSTALL "${PKGS[@]}"
ok "Packages installed"

# ============================================================
# BACKUP
# ============================================================
section "Backup existing config"

if [ -f /etc/greetd/config.toml ]; then
    sudo cp /etc/greetd/config.toml /etc/greetd/config.toml.bak
    ok "Backup created"
fi

# ============================================================
# INSTALL FILES
# ============================================================
section "Installing files"

sudo install -Dm644 "$REPO_DIR/greetd/config.toml" /etc/greetd/config.toml
sudo install -Dm755 "$REPO_DIR/scripts/greetd-wrapper.sh" /usr/local/bin/greetd-wrapper
sudo install -Dm644 "$REPO_DIR/assets/ascii.txt" /usr/local/share/login-manager/ascii.txt

ok "Files installed"

# ============================================================
# DISABLE OTHER DM
# ============================================================
section "Disabling other display managers"

for dm in gdm sddm lightdm; do
    if systemctl is-enabled "$dm" &>/dev/null; then
        sudo systemctl disable "$dm"
        warn "$dm disabled"
    fi
done

# ============================================================
# ENABLE GREETD
# ============================================================
section "Enabling greetd"

sudo systemctl enable greetd

ok "greetd enabled"

# ============================================================
# DONE
# ============================================================
echo ""
echo -e "${GREEN}${BOLD}✅ Done${RESET}"
echo ""
echo "Reboot to apply."
echo ""
echo "If broken:"
echo "  Ctrl+Alt+F2 → login"
echo "  sudo systemctl disable greetd"
echo ""
