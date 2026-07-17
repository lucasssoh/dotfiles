#!/bin/bash
# Utilise ton rasi spécifique
CHOSEN=$(echo -e "Performance\nBalanced\nPower-saver" | rofi -dmenu -theme ~/.config/rofi/performance.rasi -mesg "Power Profile")

case $CHOSEN in
    Performance) powerprofilesctl set performance ;;
    Balanced)    powerprofilesctl set balanced ;;
    Power-saver) powerprofilesctl set power-saver ;;
esac
pkill -RTMIN+1 waybar # Force la mise à jour de l'icône
