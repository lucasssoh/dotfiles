#!/bin/bash

declare -A APPS=(
    ["[Ss]team"]="󰓓"
    ["lutris"]="󰺵"
    ["heroic"]="󰺵"
    ["[Dd]iscord"]="󰙯"
    ["vesktop"]="󰙯"
)

icons=""

for pattern in "${!APPS[@]}"; do
    if pgrep -x "$pattern" > /dev/null 2>&1; then
        icon="${APPS[$pattern]}"
        if [[ "$icons" != *"$icon"* ]]; then
            icons+="$icon "
        fi
    fi
done

icons="${icons% }"
echo "$icons"
