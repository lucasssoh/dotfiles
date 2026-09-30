#!/usr/bin/env bash
# Fit every wallpaper to the screens found at install time, so the first
# session starts with the cache ready (the watcher keeps it up to date after).
. "$(dirname "$(readlink -f "$0")")/../../../lib/hook.sh"

bash "$REPO/config/hyprland/scripts/wallpaper-cache-watcher.sh" --once
ok "wallpaper cache ready"
