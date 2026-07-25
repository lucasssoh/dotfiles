#!/bin/bash
# =========================================================
# performance.sh — module waybar affichant le profil d'alimentation
# actif (performance/équilibré/économie), via power-profiles-daemon.
# =========================================================

PROFILE=$(powerprofilesctl get)

case "$PROFILE" in
    performance)
        ICON=""
        LABEL="Performance"
        ;;

    balanced)
        ICON="󰾅"
        LABEL="Balanced"
        ;;

    power-saver)
        ICON="󰌪"
        LABEL="Power Saver"
        ;;

    *)
        ICON="󰈐"
        LABEL="Unknown"
        ;;
esac

echo "{\"text\": \"$ICON\", \"tooltip\": \"Power profile: $LABEL\\nClick: change\"}"
