#!/usr/bin/env bash
# =========================================================
# watch-reload.sh — auto-reloads waybar when config.jsonc or style.css is
# edited. Launched by Hyprland's autostart (hyprland.lua), runs
# continuously. Same inotify pattern as
# hypr/scripts/wallpaper-cache-watcher.sh: event-driven (inotifywait
# blocks until a real change), no polling loop.
#
# Waybar's own "reload_style_on_change" option (config.jsonc) only
# watches the CSS side -- there's no equivalent for the JSONC config, so
# both files are watched here instead, uniformly.
# =========================================================
set -euo pipefail

WAYBAR_DIR="$HOME/.config/waybar"

reload_or_start() {
    # SIGUSR2 on a name that isn't running is a silent no-op, not an
    # error -- pgrep first so an edit made while waybar is down starts it
    # fresh instead of doing nothing.
    if pgrep -x waybar >/dev/null; then
        pkill -SIGUSR2 waybar
    else
        waybar >/dev/null 2>&1 &
        disown
    fi
}

inotifywait -m -e close_write,moved_to --format '%f' "$(readlink -f "$WAYBAR_DIR")" | \
    while read -r filename; do
        case "$filename" in
            config.jsonc|style.css) reload_or_start ;;
        esac
    done
