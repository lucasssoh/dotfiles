#!/usr/bin/env bash
# ============================================================
# POWERMENU.SH — Power menu via Rofi
# ============================================================

LOCK="🔒 Lock"
SUSPEND="💤 Suspend"
REBOOT="🔄 Reboot"
SHUTDOWN="⏻ Shutdown"
LOGOUT="🚪 Logout"

CHOICE=$(printf "$LOCK\n$SUSPEND\n$REBOOT\n$SHUTDOWN\n$LOGOUT" \
    | rofi -dmenu \
           -p "System" \
           -theme ~/.config/rofi/launcher.rasi \
           -theme-str 'window {width: 200px;}' \
           -no-fixed-num-lines)

case "$CHOICE" in
    "$LOCK")     loginctl lock-session ;;
    "$SUSPEND")  systemctl suspend ;;
    "$REBOOT")   systemctl reboot ;;
    "$SHUTDOWN") systemctl poweroff ;;
    "$LOGOUT")   hyprctl dispatch exit ;;
esac
