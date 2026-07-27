#!/usr/bin/env bash
set -euo pipefail

# =========================================================
# orbit-toggle.sh <tab> — toggles Orbit on the given tab (wifi|bluetooth),
# first closing swaync if it's open -- both panels occupy the same corner
# (top-right) and must never be open at the same time.
# =========================================================

# ~/.local/bin (where install.sh puts orbit) isn't in the PATH of
# processes launched by Hyprland -- only the zsh profile adds it, so
# `orbit` would be silently not found without this (the click did nothing).
export PATH="$HOME/.local/bin:$PATH"

swaync-client -cp >/dev/null 2>&1 || true
orbit toggle --tab "${1:?usage: orbit-toggle.sh <wifi|bluetooth>}"
