#!/usr/bin/env bash
# rofi-power.sh — Power menu avec rofi (calqué sur common.rasi + theme.rasi)

RASI="$HOME/.config/rofi/theme.rasi"

# Options
SHUTDOWN="󰐥  Éteindre"
REBOOT="󰑓  Redémarrer"
SUSPEND="󰤄  Veille"
HIBERNATE="󰒲  Hibernation"
LOCK="󰌾  Verrouiller"
LOGOUT="󰍃  Déconnexion"

CHOICE=$(printf "%s\n%s\n%s\n%s\n%s\n%s" \
    "$LOCK" "$SUSPEND" "$HIBERNATE" "$LOGOUT" "$REBOOT" "$SHUTDOWN" \
    | rofi -dmenu \
           -p "⏻  Session" \
           -theme "$RASI" \
           -no-custom \
           -i)

[[ -z "$CHOICE" ]] && exit 0

case "$CHOICE" in
    "$SHUTDOWN")
        systemctl poweroff
        ;;
    "$REBOOT")
        systemctl reboot
        ;;
    "$SUSPEND")
        systemctl suspend
        ;;
    "$HIBERNATE")
        systemctl hibernate
        ;;
    "$LOCK")
        # Adapte selon ton locker : swaylock, hyprlock, etc.
        if command -v hyprlock &>/dev/null; then
            hyprlock
        elif command -v swaylock &>/dev/null; then
            swaylock
        else
            notify-send "Power" "Aucun locker trouvé (hyprlock/swaylock)"
        fi
        ;;
    "$LOGOUT")
        hyprctl dispatch exit
        ;;
esac
