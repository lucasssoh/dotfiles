#!/usr/bin/env bash
# =========================================================
# toggle-night-mode.sh — bascule le filtre de température de couleur
# hyprsunset. L'état (activé/désactivé) est déduit de la seule présence
# du fichier STATE_FILE, pas d'un contenu à lire.
# =========================================================

STATE_FILE="$HOME/.cache/hypr-night-mode"

# =========================================================
# Activation : lance hyprsunset avec une teinte chaude
# =========================================================
if [ ! -f "$STATE_FILE" ]; then
    # Température chaude (4900K)
    hyprsunset --temperature 4900 &

    touch "$STATE_FILE"
    notify-send "Night mode" "Enabled"

# =========================================================
# Désactivation : tue hyprsunset, retour à la température native
# =========================================================
else
    pkill hyprsunset

    rm -f "$STATE_FILE"
    notify-send "Night mode" "Disabled"
fi
