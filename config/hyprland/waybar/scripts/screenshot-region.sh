#!/usr/bin/env bash
set -euo pipefail

# =========================================================
# screenshot-region.sh — capture d'une zone sélectionnée -> presse-papier
#
# Isolé dans son propre script (plutôt qu'inliné) pour le bouton "Capture"
# de swaync/config.json : swaync exécute ses commandes via
# `/bin/sh -c "<cmd>"`, donc tout guillemet double dans la commande doit
# être échappé pour ne pas casser ce wrapping -- un script évite le
# problème entièrement. Même pipeline que le raccourci SUPER+SHIFT+S
# (hypr/keybinds.lua).
# =========================================================

grim -g "$(slurp)" - | satty --filename - --fullscreen --output-filename - | wl-copy
