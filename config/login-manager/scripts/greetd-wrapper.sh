#!/usr/bin/env bash

# --- Path Definitions ---
DBUS_RUN="/usr/bin/dbus-run-session"
HYPRLAND="/usr/bin/Hyprland"

# --- Environment Setup ---
# Essential for Wayland and Hyprland portals
export XDG_SESSION_TYPE=wayland
export XDG_CURRENT_DESKTOP=Hyprland
export XDG_SESSION_DESKTOP=Hyprland

# Standard Wayland environment variables
export QT_QPA_PLATFORM=wayland
export GDK_BACKEND=wayland
export SDL_VIDEODRIVER=wayland
export CLUTTER_BACKEND=wayland

# --- Execution ---

# Use the command passed by tuigreet (from F2/F3 menus)
if [ -n "$1" ]; then
    if [ -x "$DBUS_RUN" ]; then
        exec "$DBUS_RUN" "$@"
    else
        exec "$@"
    fi
else
    # Default fallback to Hyprland
    if [ -x "$DBUS_RUN" ] && [ -x "$HYPRLAND" ]; then
        exec "$DBUS_RUN" "$HYPRLAND"
    elif [ -x "$HYPRLAND" ]; then
        exec "$HYPRLAND"
    else
        # If all else fails, drop to bash so you aren't locked out
        exec bash
    fi
fi
