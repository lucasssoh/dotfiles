#!/bin/bash

# Récupère l'état du micro via WirePlumber
STATUS=$(wpctl get-volume @DEFAULT_AUDIO_SOURCE@)

if [[ $STATUS == *"[MUTED]"* ]]; then
    # Icône micro barré / mute
    echo "{\"text\": \"󰍭\", \"class\": \"muted\"}"
else
    # Icône micro actif
    echo "{\"text\": \"󰍬\", \"class\": \"active\"}"
fi
