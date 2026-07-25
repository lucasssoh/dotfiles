#!/bin/bash
# =========================================================
# apps.sh — module waybar affichant une icône par application connue
# actuellement en cours d'exécution (jeux/launchers, Discord...).
# Sortie : une chaîne d'icônes séparées par des espaces, sans doublon
# même si plusieurs process correspondent à la même icône (ex.
# Steam + Lutris + Heroic partagent 󰺵).
# =========================================================

# process pgrep (regex) -> icône Nerd Font
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
        # Évite d'afficher deux fois la même icône si plusieurs process
        # associés au même symbole tournent en même temps
        if [[ "$icons" != *"$icon"* ]]; then
            icons+="$icon "
        fi
    fi
done

icons="${icons% }"
echo "$icons"
