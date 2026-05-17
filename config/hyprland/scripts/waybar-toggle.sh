#!/usr/bin/env bash

LOCK_FILE="/tmp/waybar-locked"
HIDDEN_FILE="/tmp/waybar-hidden"
ACTION="${1:-show}"

is_hidden() { [ -f "$HIDDEN_FILE" ]; }

show_bar() {
    if is_hidden; then
        pkill -SIGUSR1 waybar 2>/dev/null
        rm -f "$HIDDEN_FILE"
    fi
}

hide_bar() {
    [ -f "$LOCK_FILE" ] && exit 0
    if ! is_hidden; then
        pkill -SIGUSR1 waybar 2>/dev/null
        touch "$HIDDEN_FILE"
    fi
}

case "$ACTION" in
    show)   show_bar ;;
    hide)   hide_bar ;;
    lock)   touch "$LOCK_FILE"; show_bar ;;
    unlock) 
        rm -f "$LOCK_FILE"
        rm -f "$HIDDEN_FILE"
        ;;
esac
