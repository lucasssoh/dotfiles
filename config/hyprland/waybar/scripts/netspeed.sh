#!/usr/bin/env bash
# ============================================================
# NETSPEED.SH — Live network upload/download speed for Waybar
# Auto-detects the active interface (wifi or ethernet)
# ============================================================

# Find active network interface
IFACE=$(ip route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="dev") print $(i+1); exit}')

if [ -z "$IFACE" ]; then
    echo "󰤭 --"
    exit 0
fi

RX_FILE="/sys/class/net/$IFACE/statistics/rx_bytes"
TX_FILE="/sys/class/net/$IFACE/statistics/tx_bytes"

if [ ! -f "$RX_FILE" ]; then
    echo "󰤭 --"
    exit 0
fi

RX1=$(cat "$RX_FILE")
TX1=$(cat "$TX_FILE")
sleep 1
RX2=$(cat "$RX_FILE")
TX2=$(cat "$TX_FILE")

RX_RATE=$(( RX2 - RX1 ))
TX_RATE=$(( TX2 - TX1 ))

format_rate() {
    local bytes=$1
    if   (( bytes >= 1048576 )); then
        printf "%.1f MB/s" "$(echo "scale=1; $bytes/1048576" | bc)"
    elif (( bytes >= 1024 )); then
        printf "%.0f KB/s" "$(echo "scale=0; $bytes/1024" | bc)"
    else
        printf "%d B/s" "$bytes"
    fi
}

DOWN=$(format_rate $RX_RATE)
UP=$(format_rate $TX_RATE)

echo "󰇚 $DOWN  󰕒 $UP"
