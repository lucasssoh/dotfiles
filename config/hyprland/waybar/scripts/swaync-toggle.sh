#!/usr/bin/env bash
set -euo pipefail

# =========================================================
# swaync-toggle.sh — bascule le panneau swaync, en fermant d'abord Orbit
# s'il est ouvert -- les deux occupent le même coin (haut-droit) et ne
# doivent jamais être ouverts en même temps.
# =========================================================

# ~/.local/bin (où install.sh place orbit) n'est pas dans le PATH des
# processus lancés par Hyprland -- seul le profil zsh l'ajoute.
export PATH="$HOME/.local/bin:$PATH"

orbit hide >/dev/null 2>&1 || true
swaync-client -t -sw
