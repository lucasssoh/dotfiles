#!/usr/bin/env bash
set -euo pipefail

# =========================================================
# balise-toggle.sh [tab] — toggles Balise, optionally forcing it onto the
# given tab (wifi|bluetooth|ethernet), first closing the notification
# center if it's open -- declutter convention carried over from when
# both panels shared the same top-right corner; the notification center
# now sits top-left (under the bar's METRICS block) instead, but opening
# one still puts the other away.
#
# tab is now OPTIONAL: the consolidated bar block (BaliseButton.qml) has
# no per-icon tab of its own to force any more -- it just opens Balise on
# whatever tab it last showed, same as calling `balise toggle` directly.
# =========================================================

# ~/.local/bin (where install.sh puts balise) isn't in the PATH of
# processes launched by Hyprland -- only the zsh profile adds it, so
# `balise` would be silently not found without this (the click did nothing).
export PATH="$HOME/.local/bin:$PATH"

qs -c bar ipc call bar closeNotificationCenter >/dev/null 2>&1 || true
if [ -n "${1:-}" ]; then
    balise toggle --tab "$1"
else
    balise toggle
fi
