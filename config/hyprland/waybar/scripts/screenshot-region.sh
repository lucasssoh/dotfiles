#!/usr/bin/env bash
set -euo pipefail

# =========================================================
# screenshot-region.sh — capture of a selected region -> clipboard
#
# Split into its own script (rather than inlined) for the "Capture"
# button in the notification center (NotificationCenter.qml, was
# swaync/config.json's buttons-grid): the launching side runs commands
# via a shell wrapper, so any double quote in the command would need
# escaping to not break that wrapping -- a script avoids the problem
# entirely. Same pipeline as the SUPER+SHIFT+S shortcut
# (hypr/keybinds.lua).
# =========================================================

grim -g "$(slurp)" - | satty --filename - --fullscreen --output-filename - | wl-copy
