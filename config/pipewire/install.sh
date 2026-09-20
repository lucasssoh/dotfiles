#!/usr/bin/env bash
set -Eeuo pipefail

# The single safe_link (scripts/lib/link.sh) -- returns early when the link is
# already correct, and records what it did for `cc-pkg-mng verify`.
. "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../../scripts/lib/link.sh"
. "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../../scripts/lib/pkg.sh"

BLUE="\e[34m"
GREEN="\e[32m"
RESET="\e[0m"

info() { echo -e "${BLUE}[INFO]${RESET}  $*"; }
ok()   { echo -e "${GREEN}[ OK ]${RESET}  $*"; }

# pipewire-utils is a HARD dependency of the bar's mixer drawer, not a
# convenience: modules/mixer/ drives the equalizer below by writing into a
# resident `pw-cli`, and there is no other way to move a filter-chain control
# port while the graph is running.
#
# Asked for unconditionally, unlike config/wireplumber/install.sh which asks
# for it only when `wireplumber` itself is missing. That guard is why this
# machine ran for months without pw-cli or pw-dump: wireplumber was already
# there, so the whole pkg_ensure line was skipped -- and it took
# bt-audio-switch.service down with it, which needs pw-dump and had been
# exiting after 6ms ever since. pkg_ensure queries before it installs, so
# naming it here costs nothing on a machine that already has it.
pkg_ensure pipewire pipewire-utils

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SRC_DIR="$DOTFILES_DIR/config/pipewire"
TARGET_DIR="$HOME/.config/pipewire/pipewire.conf.d"

mkdir -p "$TARGET_DIR"

safe_link "$SRC_DIR/50-equalizer.conf" "$TARGET_DIR/50-equalizer.conf"

# The daemon reads conf.d at startup only -- a new filter chain does not
# appear until it is restarted. Guarded on the service actually running so a
# provisioning run inside a container does not fail here.
if systemctl --user is-active pipewire &> /dev/null; then
    info "Restarting pipewire to pick up the equalizer..."
    systemctl --user restart pipewire pipewire-pulse wireplumber
fi

ok "PipeWire equalizer configured."
