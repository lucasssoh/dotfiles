#!/bin/bash
# =========================================================
# apps.sh — waybar module showing one icon per known application
# currently running (games/launchers, Discord...).
# Output: a string of icons separated by spaces, deduplicated even if
# several processes map to the same icon (e.g. Steam + Lutris + Heroic
# share 󰺵).
# =========================================================

# pgrep process pattern (regex) -> Nerd Font icon
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
        # Avoids showing the same icon twice if several processes mapped
        # to the same symbol are running at once
        if [[ "$icons" != *"$icon"* ]]; then
            icons+="$icon "
        fi
    fi
done

icons="${icons% }"
echo "$icons"
