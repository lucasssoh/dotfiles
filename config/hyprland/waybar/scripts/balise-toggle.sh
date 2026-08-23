#!/usr/bin/env bash
set -euo pipefail

# =========================================================
# balise-toggle.sh <tab> — toggles Balise on the given tab
# (wifi|bluetooth|ethernet),
# first closing swaync if it's open -- both panels occupy the same corner
# (top-right) and must never be open at the same time.
# =========================================================

# ~/.local/bin (where install.sh puts balise) isn't in the PATH of
# processes launched by Hyprland -- only the zsh profile adds it, so
# `balise` would be silently not found without this (the click did nothing).
export PATH="$HOME/.local/bin:$PATH"

swaync-client -cp >/dev/null 2>&1 || true
balise toggle --tab "${1:?usage: balise-toggle.sh <wifi|bluetooth|ethernet>}"
