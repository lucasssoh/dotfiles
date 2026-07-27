#!/bin/bash
# =========================================================
# mic-status.sh — waybar module showing whether the default mic is
# active or muted, via WirePlumber (wpctl).
# =========================================================

STATUS=$(wpctl get-volume @DEFAULT_AUDIO_SOURCE@)

if [[ $STATUS == *"[MUTED]"* ]]; then
    # Muted / crossed-out mic icon
    echo "{\"text\": \"󰍭\", \"class\": \"muted\"}"
else
    # Active mic icon
    echo "{\"text\": \"󰍬\", \"class\": \"active\"}"
fi
