#!/usr/bin/env bash

win=$(hyprctl activewindow -j 2>/dev/null)

title=$(echo "$win" | jq -r '.title // empty')
class=$(echo "$win" | jq -r '.class // empty')

if [[ -z "$title" ]]; then
    echo '{"text": "", "class": "empty"}'
    exit 0
fi

MAX=35
[[ ${#title} -gt $MAX ]] && title="${title:0:$((MAX-2))}…"

ICON=""

case "${class,,}" in  # Convertit la classe en minuscules pour plus de robustesse
    # --- Navigateurs Web ---
    *firefox*)          ICON="󰈹" ;;
    *chromium*|*chrome*|*brave*|*opera*) ICON="󰊯" ;;
    *zen*)              ICON="󰈹" ;; # Navigateur Zen

    # --- Terminaux ---
    *wezterm*|*ghostty*|*alacritty*|*kitty*|*foot*|*term*) ICON="" ;;

    # --- Développement & Éditeurs ---
    *code*|*visual-studio-code*) ICON="󰨞" ;;
    *nvim*|*vim*)       ICON="" ;;
    *emacs*)            ICON="" ;;
    *sublime-text*)     ICON="" ;;

    # --- Multimédia ---
    *spotify*)          ICON="󰓇" ;;
    *vlc*|*mpv*)        ICON="󰕼" ;;
    *pavucontrol*)      ICON="󰓃" ;;

    # --- Communication ---
    *discord*|*webcord*) ICON="󰙯" ;;
    *slack*)            ICON="󰒱" ;;
    *telegram*|*tg*)    ICON="󰔁" ;;
    *signal*)           ICON="󰈼" ;;
    *thunderbird*|*evolution*|*geary*|*mail*) ICON="󰇮" ;;

    # --- Fichiers & Système ---
    *thunar*|*nautilus*|*dolphin*|*pcmanfm*) ICON="󰉋" ;;
    *btop*|*htop*)      ICON="󰄪" ;;
    *settings*|*control-center*) ICON="󰒓" ;;

    # --- Autres ---
    *obsidian*)         ICON="󱓧" ;;
    *gimp*|*inkscape*)  ICON="󰔉" ;;
    *steam*)            ICON="󰓓" ;;
    *lutris*|*heroic*|*bottles*|*itch*) ICON="󰺵" ;;

    # --- Par défaut ---
    *)                  ICON="󰓎" ;;
esac
TEXT="$ICON  $title"

echo "{\"text\": \"$TEXT\", \"class\": \"filled\"}"
