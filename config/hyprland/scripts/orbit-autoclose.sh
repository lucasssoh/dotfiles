#!/usr/bin/env bash
set -uo pipefail

# =========================================================
# orbit-autoclose.sh — closes Orbit as soon as another window takes focus
# (same behavior as the swaync panel, which natively closes on an outside
# click).
#
# Orbit is a plain layer-shell surface: GTK/gtk4-layer-shell never emits a
# focus-loss event for this type of surface (its "is-active" property
# never goes back to false). So we rely on Hyprland events (activewindow)
# instead, which are reliable. Opening Orbit itself never triggers an
# activewindow event (layer-shell surfaces don't appear in this stream),
# so this script can't accidentally close Orbit right after it opens.
# =========================================================

# ~/.local/bin (where install.sh places orbit) isn't in the PATH of
# processes launched by Hyprland -- only the zsh profile adds it.
export PATH="$HOME/.local/bin:$PATH"

SOCKET=""
for _ in $(seq 1 30); do
    SOCKET=$(find "/run/user/$(id -u)/hypr/" -name ".socket2.sock" 2>/dev/null | head -1)
    [ -n "$SOCKET" ] && break
    sleep 1
done
[ -z "$SOCKET" ] && exit 1

socat -u UNIX-CONNECT:"$SOCKET" STDOUT | while IFS= read -r line; do
    case "$line" in
        activewindow\>\>*)
            orbit hide >/dev/null 2>&1 || true
            ;;
    esac
done
