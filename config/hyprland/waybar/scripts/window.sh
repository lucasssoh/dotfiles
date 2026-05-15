#!/usr/bin/env bash

# Quitter proprement sur pipe brisé (SIGPIPE)
trap 'exit 0' SIGPIPE

format_window() {
    local win
    win=$(hyprctl activewindow -j 2>/dev/null) || { printf '{"text":"","class":"empty"}\n'; return; }

    local title class
    title=$(printf '%s' "$win" | jq -re '.title // empty' 2>/dev/null) || { printf '{"text":"","class":"empty"}\n'; return; }
    class=$(printf '%s' "$win" | jq -re '.class // empty' 2>/dev/null) || class=""

    local MAX=35
    [[ ${#title} -gt $MAX ]] && title="${title:0:$((MAX-2))}…"

    local ICON
    case "${class,,}" in
        *firefox*|*zen*)                              ICON="󰈹" ;;
        *chromium*|*chrome*|*brave*|*opera*)          ICON="󰊯" ;;
        *wezterm*|*ghostty*|*alacritty*|*kitty*|*foot*|*term*) ICON="" ;;
        *code*|*visual-studio-code*)                  ICON="󰨞" ;;
        *nvim*|*vim*)                                 ICON="" ;;
        *spotify*)                                    ICON="󰓇" ;;
        *vlc*|*mpv*)                                  ICON="󰕼" ;;
        *pavucontrol*)                                ICON="󰓃" ;;
        *discord*|*webcord*)                          ICON="󰙯" ;;
        *slack*)                                      ICON="󰒱" ;;
        *telegram*|*tg*)                              ICON="󰔁" ;;
        *signal*)                                     ICON="󰈼" ;;
        *thunderbird*|*evolution*|*geary*|*mail*)     ICON="󰇮" ;;
        *thunar*|*nautilus*|*dolphin*|*pcmanfm*)      ICON="󰉋" ;;
        *btop*|*htop*)                                ICON="󰄪" ;;
        *settings*|*control-center*)                  ICON="󰒓" ;;
        *obsidian*)                                   ICON="󱓧" ;;
        *gimp*|*inkscape*)                            ICON="󰔉" ;;
        *steam*)                                      ICON="󰓓" ;;
        *lutris*|*heroic*|*bottles*|*itch*)           ICON="󰺵" ;;
        *)                                            ICON="󰓎" ;;
    esac

    printf '{"text":"%s  %s","class":"filled"}\n' "$ICON" "$title"
}

# État initial
format_window

# Listener événementiel via le socket Hyprland
socat -U - "UNIX-CONNECT:$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock" 2>/dev/null \
| grep -E --line-buffered '^(activewindow|windowtitle)>>' \
| while IFS= read -r _; do
    format_window || exit 0
done
