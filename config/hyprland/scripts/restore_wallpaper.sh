#!/usr/bin/env bash

STATE_FILE="$HOME/.cache/current_wallpaper"

# Crée le fichier si nécessaire (vide par défaut)
mkdir -p "$(dirname "$STATE_FILE")"
[ ! -f "$STATE_FILE" ] && touch "$STATE_FILE"

# Lit le wallpaper sauvegardé
WALLPAPER=$(cat "$STATE_FILE")

# Si non vide, applique le wallpaper
[ -n "$WALLPAPER" ] && swww img "$WALLPAPER" --transition-type fade --transition-duration 0.2
