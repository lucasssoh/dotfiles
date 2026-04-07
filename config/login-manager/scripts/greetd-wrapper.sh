#!/usr/bin/env bash
# ============================================================
# greetd-session.sh
# System-widbin"

# Optional debug log (very useful if something breaks)
LOG_FILE="/tmp/greetd-session.log"
exec >> "$LOG_FILE" 2>&1

echo "=== greetd-session started at $(date) ==="

# ============================================================
# ENV FIXES (important for Wayland sessions)
# ============================================================

export XDG_SESSION_TYPE=wayland
export XDG_CURRENT_DESKTOP=Hyprland

# ============================================================
# SESSION LAUNCH
# ============================================================

# If tuigreet passes a command → execute it
if [ -n "$1" ]; then
    echo "Launching session from tuigreet: $*"
    exec "$@"
fi

# Default fallback session
echo "No session provided, falling back to Hyprland"

if command -v Hyprland &>/dev/null; then
    exec dbus-run-session Hyprland
fi

# Final fallback (never leave blank screen)
echo "Hyprland not found, falling back to shell"
exec bash
