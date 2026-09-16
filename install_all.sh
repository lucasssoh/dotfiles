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
# The module list and its ordering constraints now live in
# scripts/lib/modules.sh, together with the reasoning that used to sit in a
# comment block here. The array itself was never the problem; what was
# missing was anything checking it against the filesystem. registry_validate
# supplies that, and it is why the hyprland/kde "special cases" below are
# gone: they were never special, only last, which MODULE_ORDER now says
# directly.
source "$DOTFILES_DIR/scripts/lib/modules.sh"
section "Modules"

if ! registry_validate; then
    err "Module registry is inconsistent (see above) — refusing to run a partial install."
fi

for module in "${MODULE_ORDER[@]}"; do
    # Guard the FILE, not its parent directory. The old `[ -d ]` check was
    # followed by an unguarded `chmod +x "$MODULE_PATH/install.sh"`, so a
    # module directory that existed without its script killed the whole user
    # phase under `set -e` -- skipping status_summary and the exit-code
    # plumbing at the end of this file entirely.
    if MODULE_SCRIPT="$(module_script "$module")"; then
        chmod +x "$MODULE_SCRIPT" 2>/dev/null || true
        run_step "$module" "$MODULE_SCRIPT" || true
    else
        skip_step "$module" "config/$module/install.sh not found"
    fi
done

# -----------------------------
# Done
# -----------------------------
rc=0
status_summary || rc=$?
exit "$rc"
