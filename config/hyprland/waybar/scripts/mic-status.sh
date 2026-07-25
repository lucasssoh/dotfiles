#!/bin/bash
# =========================================================
# mic-status.sh — module waybar indiquant si le micro par défaut est
# actif ou coupé, via WirePlumber (wpctl).
# =========================================================

STATUS=$(wpctl get-volume @DEFAULT_AUDIO_SOURCE@)

if [[ $STATUS == *"[MUTED]"* ]]; then
    # Icône micro barré / mute
    echo "{\"text\": \"󰍭\", \"class\": \"muted\"}"
else
    # Icône micro actif
    echo "{\"text\": \"󰍬\", \"class\": \"active\"}"
fi
