#!/usr/bin/env bash
set -euo pipefail

# =========================================================
# swaync-toggle.sh — toggles the swaync panel, first closing Orbit if
# it's open -- both occupy the same corner (top-right) and must never
# be open at the same time.
# =========================================================

# ~/.local/bin (where install.sh puts orbit) isn't in the PATH of
# processes launched by Hyprland -- only the zsh profile adds it.
export PATH="$HOME/.local/bin:$PATH"

orbit hide >/dev/null 2>&1 || true
swaync-client -t -sw
