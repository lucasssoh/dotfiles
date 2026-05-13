#!/usr/bin/env bash
# rofi-bluetooth.sh — Menu bluetooth via bluetoothctl avec rofi

RASI="$HOME/.config/rofi/theme.rasi"

if ! command -v bluetoothctl &>/dev/null; then
    notify-send "rofi-bluetooth" "bluetoothctl introuvable"
    exit 1
fi

# --- Helpers ---
_bt_powered() {
    bluetoothctl show 2>/dev/null | grep -q "Powered: yes"
}

_bt_devices() {
    # Liste périphériques connus avec leur état (connecté ou non)
    bluetoothctl devices 2>/dev/null | while read -r _ mac name; do
        info=$(bluetoothctl info "$mac" 2>/dev/null)
        connected=$(echo "$info" | grep -c "Connected: yes")
        paired=$(echo "$info"    | grep -c "Paired: yes")
        trusted=$(echo "$info"   | grep -c "Trusted: yes")

        icon="󰂯"
        [[ "$connected" -gt 0 ]] && icon="󰂱"

        conn_label=""
        [[ "$connected" -gt 0 ]] && conn_label=" ●"

        echo "${icon}  ${name}${conn_label}|${mac}"
    done
}

_bt_toggle_device() {
    local mac="$1"
    local name="$2"
    if bluetoothctl info "$mac" 2>/dev/null | grep -q "Connected: yes"; then
        bluetoothctl disconnect "$mac" && notify-send "Bluetooth" "Déconnecté : $name"
    else
        bluetoothctl connect "$mac" && notify-send "Bluetooth" "Connecté : $name" || \
            notify-send "Bluetooth" "Échec connexion : $name"
    fi
}

# --- Vérif power ---
if ! _bt_powered; then
    CHOICE=$(printf "󰂯  Activer Bluetooth\n󰜺  Quitter" \
        | rofi -dmenu -p "󰂲  Bluetooth" -theme "$RASI" -no-custom)
    [[ "$CHOICE" == *"Activer"* ]] && bluetoothctl power on
    exit 0
fi

# --- Build menu ---
POWER_LABEL="󰂲  Désactiver Bluetooth"
SCAN_LABEL="󱢴  Scanner de nouveaux appareils"

DEVICES_RAW=$(_bt_devices)
DEVICES_DISPLAY=$(echo "$DEVICES_RAW" | cut -d'|' -f1)

MENU=$(printf "%s\n%s\n%s" "$POWER_LABEL" "$SCAN_LABEL" "$DEVICES_DISPLAY")

CHOICE=$(echo "$MENU" | rofi -dmenu -i -p "󰂱  Bluetooth" -theme "$RASI" -no-custom)

[[ -z "$CHOICE" ]] && exit 0

case "$CHOICE" in
    *"Désactiver Bluetooth"*)
        bluetoothctl power off
        notify-send "Bluetooth" "Désactivé"
        ;;
    *"Scanner"*)
        notify-send "Bluetooth" "Scan en cours (10s)…"
        bluetoothctl --timeout 10 scan on &>/dev/null
        # Relancer le menu après scan
        exec "$0"
        ;;
    *)
        # Retrouver le MAC depuis la ligne choisie
        MAC=$(echo "$DEVICES_RAW" | grep -F "${CHOICE}" | head -1 | cut -d'|' -f2)
        NAME=$(echo "$CHOICE" | sed 's/^..  //' | sed 's/ ●//')
        [[ -n "$MAC" ]] && _bt_toggle_device "$MAC" "$NAME"
        ;;
esac
