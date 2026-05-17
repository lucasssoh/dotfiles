#!/usr/bin/env bash

set -euo pipefail

RASI="$HOME/.config/rofi/power.rasi"

# =========================================================
# OPTIONS
# =========================================================

declare -A ACTIONS=(
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
    -p "⏻" \
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
        notify-send "Lock" "Aucun locker trouvé"
        return 1
    fi
}

confirm() {
    echo -e "Non\nOui" | rofi -dmenu \
        -theme "$RASI" \
        -p "$1" \
        -no-custom \
        -selected-row 0 \
        | grep -qx "Oui"
}

# =========================================================
# ACTIONS
# =========================================================

case "$ACTION" in

    lock)
        lock_screen
        ;;

    suspend)
        if confirm "Mettre en veille ?" ; then
            lock_screen &
            sleep 1
            systemctl suspend
        fi
        ;;

    hibernate)
        if confirm "Hiberner ?" ; then
            lock_screen &
            sleep 1
            systemctl hibernate
        fi
        ;;

    logout)
        if confirm "Se déconnecter ?" ; then
            loginctl terminate-user "$USER"
        fi
        ;;

    reboot)
        if confirm "Redémarrer ?" ; then
            systemctl reboot
        fi
        ;;

    shutdown)
        if confirm "Éteindre ?" ; then
            systemctl poweroff
        fi
        ;;

esac
