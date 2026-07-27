#!/usr/bin/env bash
# =========================================================
# rofi-power.sh — Rofi power menu (lock, sleep, hibernate, log out,
# reboot, shutdown), with confirmation for any destructive or
# disruptive action.
# =========================================================

set -euo pipefail

# Path to the main menu theme
RASI="$HOME/.config/rofi/power.rasi"
# Path to the confirmation menu theme
RASI_CONFIRM="$HOME/.config/rofi/confirm.rasi"

# =========================================================
# OPTIONS
# =========================================================

declare -A ACTIONS=(  # displayed icon -> associated action
    ["󰌾"]="lock"
    ["󰤄"]="suspend"
    ["󰒲"]="hibernate"
    ["󰍃"]="logout"
    ["󰑓"]="reboot"
    ["󰐥"]="shutdown"
)

OPTIONS=$(printf "%s\n" \
    "󰌾" \
    "󰤄" \
    "󰒲" \
    "󰍃" \
    "󰑓" \
    "󰐥")

# =========================================================
# MENU
# =========================================================

CHOICE=$(echo "$OPTIONS" | rofi -dmenu \
    -theme "$RASI" \
    -mesg "Power" \
    -no-custom \
    -format s \
    -i)

[[ -z "$CHOICE" ]] && exit 0

ACTION="${ACTIONS[$CHOICE]}"

# =========================================================
# HELPERS
# =========================================================

lock_screen() {
    if command -v hyprlock >/dev/null 2>&1; then
        hyprlock
    elif command -v swaylock >/dev/null 2>&1; then
        swaylock
    else
        notify-send "Lock" "No locker found"
        return 1
    fi
}

confirm() {
    echo -e "No\nGo ahead" | rofi -dmenu \
        -theme "$RASI_CONFIRM" \
        -mesg "$1" \
        -no-custom \
        -selected-row 0 \
        | grep -qx "Go ahead"
}

# =========================================================
# ACTIONS
# =========================================================

case "$ACTION" in

    lock)
        lock_screen
        ;;

    suspend)
        if confirm "Suspend system?" ; then
            lock_screen &
            sleep 1
            systemctl suspend
        fi
        ;;

    hibernate)
        if confirm "Hibernate system?" ; then
            lock_screen &
            sleep 1
            systemctl hibernate
        fi
        ;;

    logout)
        if confirm "Log out?" ; then
            loginctl terminate-user "$USER"
        fi
        ;;

    reboot)
        if confirm "Reboot system?" ; then
            systemctl reboot
        fi
        ;;

    shutdown)
        if confirm "Power off?" ; then
            systemctl poweroff
        fi
        ;;

esac
