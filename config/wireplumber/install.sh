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

BLUE="\e[34m"
GREEN="\e[32m"
RESET="\e[0m"

info() { echo -e "${BLUE}[INFO]${RESET}  $*"; }
ok()   { echo -e "${GREEN}[ OK ]${RESET}  $*"; }

if ! command -v wireplumber &> /dev/null; then
    pkg_ensure wireplumber pipewire-utils
fi

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SRC_DIR="$DOTFILES_DIR/config/wireplumber"
TARGET_DIR="$HOME/.config/wireplumber/wireplumber.conf.d"
SCRIPTS_TARGET="$HOME/.config/wireplumber/scripts"
SYSTEMD_TARGET="$HOME/.config/systemd/user"

mkdir -p "$TARGET_DIR" "$SCRIPTS_TARGET" "$SYSTEMD_TARGET"


safe_link "$SRC_DIR/10-bluetooth-policy.conf"  "$TARGET_DIR/10-bluetooth-policy.conf"
safe_link "$SRC_DIR/51-bluetooth-auto.conf"    "$TARGET_DIR/51-bluetooth-auto.conf"
safe_link "$SRC_DIR/52-bluetooth-profile.conf" "$TARGET_DIR/52-bluetooth-profile.conf"

safe_link "$SRC_DIR/systemd/bt-audio-switch.sh" "$SCRIPTS_TARGET/bt-audio-switch.sh"
chmod +x "$SCRIPTS_TARGET/bt-audio-switch.sh"

safe_link "$SRC_DIR/systemd/bt-audio-switch.service" "$SYSTEMD_TARGET/bt-audio-switch.service"

systemctl --user daemon-reload
systemctl --user enable --now bt-audio-switch.service

if systemctl --user is-active pipewire &> /dev/null; then
    info "Restarting audio stack..."
    systemctl --user restart wireplumber pipewire pipewire-pulse
fi

ok "WirePlumber configured."
