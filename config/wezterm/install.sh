#!/usr/bin/env bash
set -Eeuo pipefail

# The single safe_link (scripts/lib/link.sh). It replaces the copy that used
# to live here: that one removed and re-created the link on every run, even
# when it was already correct. This one returns early, and records what it
# did so `cc-pkg-mng verify` can check it later.
. "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../../scripts/lib/link.sh"

# Package helper: queries before it installs, so an already-provisioned
# machine performs zero package-manager calls and never prompts for sudo.
. "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../../scripts/lib/pkg.sh"

GREEN="\e[32m"
RESET="\e[0m"

ok() { echo -e "${GREEN}[ OK ]${RESET}  $*"; }

# 1. Install WezTerm
# The third-party repo is only touched when wezterm is actually absent:
# `dnf copr enable` on an already-enabled copr is harmless but still wakes
# dnf and needs root, which is exactly what this module must stop doing on
# every run.
if ! pkg_installed wezterm; then
    case "$(pkg_mgr)" in
        dnf) sudo_maybe dnf copr enable wezfurlong/wezterm-nightly -y ;;
        apt)
            curl -fsSL https://apt.fury.io/wez/gpg.key | sudo_maybe gpg --yes --dearmor -o /usr/share/keyrings/wezterm-fury.gpg
            echo 'deb [signed-by=/usr/share/keyrings/wezterm-fury.gpg] https://apt.fury.io/wez/ * *' | sudo_maybe tee /etc/apt/sources.list.d/wezterm.list
            sudo_maybe apt-get update
            ;;
    esac
fi
pkg_ensure wezterm

# 2. Symlinks
DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
mkdir -p ~/.config/wezterm


# Link the config
safe_link "$DOTFILES_DIR/config/wezterm/wezterm.lua" ~/.wezterm.lua
safe_link "$DOTFILES_DIR/config/wezterm/wezterm.lua" ~/.config/wezterm/wezterm.lua

ok "WezTerm configured."
