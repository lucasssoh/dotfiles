#!/usr/bin/env bash

# --- Environment Setup ---
export XDG_SESSION_TYPE=wayland
export XDG_CURRENT_DESKTOP=Hyprland
export XDG_SESSION_DESKTOP=Hyprland

# Hardware acceleration (Useful for Intel/AMD)
export WLR_NO_HARDWARE_CURSORS=1 

# Fix for some apps failing to start in Wayland
export QT_QPA_PLATFORM=wayland
export GDK_BACKEND=wayland
export SDL_VIDEODRIVER=wayland
export CLUTTER_BACKEND=wayland

# --- Execution ---

# Case 1: tuigreet passed a specific command (via F3 menu)
if [ -n "$1" ]; then
    # We use dbus-run-session to ensure a session bus is available
    exec dbus-run-session "$@"
else
    # Case 2: Fallback to Hyprland if no command was provided
    if command -v Hyprland &>/dev/null; then
        exec dbus-run-session Hyprland
    else
        # Last resort: if Hyprland is missing, don't stay stuck
        exec bash
    fi
fi
