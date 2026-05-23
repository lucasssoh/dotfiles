#!/usr/bin/env bash

STATE_FILE="$HOME/.cache/hypr-night-mode"

# =========================================================
# MODE NUIT ACTIVÉ
# =========================================================
if [ ! -f "$STATE_FILE" ]; then
    # Température chaude (4900K)
    hyprsunset --temperature 4900 &

    touch "$STATE_FILE"
    notify-send "Night mode" "Enabled"

# =========================================================
# MODE NUIT DÉSACTIVÉ
# =========================================================
else
    pkill hyprsunset

    rm -f "$STATE_FILE"
    notify-send "Night mode" "Disabled"
fi
