#!/usr/bin/env bash
# =========================================================
# toggle-night-mode.sh — toggles hyprsunset's color temperature filter.
# The state (enabled/disabled) is inferred purely from the presence of
# STATE_FILE, no content to read.
# =========================================================

STATE_FILE="$HOME/.cache/hypr-night-mode"

# =========================================================
# Enable: launches hyprsunset with a warm tint
# =========================================================
if [ ! -f "$STATE_FILE" ]; then
    # Warm temperature (4900K)
    hyprsunset --temperature 4900 &

    touch "$STATE_FILE"
    notify-send "Night mode" "Enabled"

# =========================================================
# Disable: kills hyprsunset, back to native temperature
# =========================================================
else
    pkill hyprsunset

    rm -f "$STATE_FILE"
    notify-send "Night mode" "Disabled"
fi
