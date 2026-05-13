#!/usr/bin/env bash
# rofi-wifi.sh
RASI="$HOME/.config/rofi/theme.rasi"

# ─────────────────────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────────────────────

wifi_enabled() {
    nmcli radio wifi | grep -q enabled
}

signal_icon() {
    local s="$1"

    if   (( s >= 80 )); then echo "󰤨"
    elif (( s >= 60 )); then echo "󰤥"
    elif (( s >= 40 )); then echo "󰤢"
    elif (( s >= 20 )); then echo "󰤟"
    else                      echo "󰤯"
    fi
}

# ─────────────────────────────────────────────────────────────
# Build network list
# ─────────────────────────────────────────────────────────────

build_networks() {

    nmcli device wifi rescan >/dev/null 2>&1

    SAVED=$(nmcli -t -f NAME connection show | sort -u)
    ACTIVE=$(nmcli -t -f NAME connection show --active | sort -u)

    nmcli -t -f SSID,SIGNAL,SECURITY device wifi list \
    | while IFS=: read -r ssid signal security; do

        [[ -z "$ssid" ]] && continue

        icon=$(signal_icon "$signal")

        tags=""

        known="false"

        if echo "$SAVED" | grep -qxF "$ssid"; then
            known="true"
            tags="[saved]"
        fi

        if echo "$ACTIVE" | grep -qxF "$ssid"; then
            tags="[connected]"
            known="true"
        fi

        lock=""
        [[ -n "$security" && "$security" != "--" ]] && lock="󰌾"

        if [[ "$known" == "true" ]]; then
            category="0_KNOWN"
        else
            category="1_UNKNOWN"
        fi

        printf "%s|%s  %-25s %s %s\n" \
            "$category" \
            "$icon" \
            "$ssid" \
            "$lock" \
            "$tags"

    done | sort -u
}

# ─────────────────────────────────────────────────────────────
# Main menu
# ─────────────────────────────────────────────────────────────

show_main_menu() {

    local toggle

    if wifi_enabled; then
        toggle="󰤭  Disable WiFi"
    else
        toggle="󰤨  Enable WiFi"
    fi

    NETWORKS=$(build_networks)

    MENU=$(
        printf "%s\n" "$toggle"
        echo "$NETWORKS" \
            | grep "^0_KNOWN" \
            | cut -d'|' -f2
        echo "$NETWORKS" \
            | grep "^1_UNKNOWN" \
            | cut -d'|' -f2
    )

    echo "$MENU" | rofi \
        -dmenu \
        -i \
        -p "󰤨 WiFi" \
        -theme "$RASI"
}

# ─────────────────────────────────────────────────────────────
# Network submenu
# ─────────────────────────────────────────────────────────────

network_menu() {

    local ssid="$1"

    if nmcli -t -f NAME connection show --active | grep -qxF "$ssid"; then
        ACTIONS="󰤭  Disconnect\n󰆴  Forget\n󰜉  Back"
    else
        ACTIONS="󰤨  Connect\n󰆴  Forget\n󰜉  Back"
    fi

    CHOICE=$(echo -e "$ACTIONS" | rofi \
        -dmenu \
        -i \
        -p "$ssid" \
        -theme "$RASI")

    case "$CHOICE" in

        *Connect*)

            if nmcli connection show | grep -qF "$ssid"; then

                nmcli connection up "$ssid"

            else

                PASS=$(rofi \
                    -dmenu \
                    -password \
                    -p "󰌾 Password" \
                    -theme "$RASI")

                [[ -z "$PASS" ]] && exit 0

                nmcli device wifi connect "$ssid" password "$PASS"
            fi
            ;;

        *Disconnect*)

            nmcli connection down "$ssid"
            ;;

        *Forget*)

            nmcli connection delete "$ssid"
            ;;

    esac
}

# ─────────────────────────────────────────────────────────────
# Entry
# ─────────────────────────────────────────────────────────────

CHOICE=$(show_main_menu)

[[ -z "$CHOICE" ]] && exit 0

if [[ "$CHOICE" == *"Enable WiFi"* ]]; then
    nmcli radio wifi on
    exit 0
fi

if [[ "$CHOICE" == *"Disable WiFi"* ]]; then
    nmcli radio wifi off
    exit 0
fi

SSID=$(echo "$CHOICE" \
    | sed 's/^󰤨//;s/^󰤥//;s/^󰤢//;s/^󰤟//;s/^󰤯//' \
    | sed 's/󰌾//g' \
    | sed 's/\[saved\]//g' \
    | sed 's/\[connected\]//g' \
    | xargs)

[[ -z "$SSID" ]] && exit 0

network_menu "$SSID"
