#!/bin/bash
# Menu simple pour switcher ou muter
CHOSEN=$(echo -e "Toggle Mute\nSettings" | rofi -dmenu -theme ~/.config/rofi/mic.rasi -p "Microphone")

case $CHOSEN in
    "Toggle Mute") wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle ;;
    "Settings")    pavucontrol -t 4 ;; # Ouvre l'onglet périph d'entrée
esac
