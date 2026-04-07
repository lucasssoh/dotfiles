#!/usr/bin/env bash

# Variables d'environnement pour Wayland
export XDG_SESSION_TYPE=wayland
export XDG_CURRENT_DESKTOP=Hyprland

# Lancement via dbus pour éviter les problèmes de portails
if [ -n "$1" ]; then
    exec dbus-run-session "$@"
else
    exec dbus-run-session Hyprland
fi
