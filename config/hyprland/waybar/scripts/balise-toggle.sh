#!/usr/bin/env bash
set -euo pipefail

# =========================================================
# balise-toggle.sh [tab] — toggles Balise, optionally forcing it onto the
# given tab (wifi|bluetooth|ethernet), first closing swaync if it's open --
# both panels occupy the same corner (top-right) and must never be open at
# the same time.
#
# tab is now OPTIONAL: the consolidated bar block (BaliseButton.qml) has
# no per-icon tab of its own to force any more -- it just opens Balise on
# whatever tab it last showed, same as calling `balise toggle` directly.
# =========================================================

# ~/.local/bin (where install.sh puts balise) isn't in the PATH of
# processes launched by Hyprland -- only the zsh profile adds it, so
# `balise` would be silently not found without this (the click did nothing).
export PATH="$HOME/.local/bin:$PATH"

swaync-client -cp >/dev/null 2>&1 || true
if [ -n "${1:-}" ]; then
    balise toggle --tab "$1"
else
    balise toggle
fi
