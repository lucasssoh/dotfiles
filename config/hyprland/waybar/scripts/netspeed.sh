#!/usr/bin/env bash
# ============================================================
# NETSPEED.SH — Live network speed for Waybar
# Reads /proc/net/dev directly — no sleep, instant output
# Uses a state file to compute delta between calls
# ============================================================

IFACE=$(ip route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="dev") print $(i+1); exit}')

if [ -z "$IFACE" ]; then
    echo "󰤭"
    exit 0
fi

STATE_FILE="/tmp/waybar-netspeed-$IFACE"
NOW=$(date +%s%N)  # nanoseconds

# Read current bytes from /proc/net/dev (no sleep needed)
read RX TX <<< $(awk -v iface="$IFACE:" '
    $1 == iface { print $2, $10 }
' /proc/net/dev)

if [ -z "$RX" ]; then
    echo "󰤭"
    exit 0
fi

# First call: just save state, output placeholder
if [ ! -f "$STATE_FILE" ]; then
    echo "$NOW $RX $TX" > "$STATE_FILE"
    echo "↓ -- ↑ --"
    exit 0
fi

read PREV_TIME PREV_RX PREV_TX < "$STATE_FILE"
echo "$NOW $RX $TX" > "$STATE_FILE"

ELAPSED=$(( (NOW - PREV_TIME) / 1000000 ))  # ms
[ "$ELAPSED" -lt 1 ] && ELAPSED=1

RX_RATE=$(( (RX - PREV_RX) * 1000 / ELAPSED ))  # bytes/s
TX_RATE=$(( (TX - PREV_TX) * 1000 / ELAPSED ))  # bytes/s

format_rate() {
    local b=$1
    if   (( b >= 1048576 )); then 
        printf "%4.1f MB/s" "$(echo "scale=1; $b/1048576" | bc)"
    elif (( b >= 1024 ));    then 
        printf "%4d KB/s" $(( b / 1024 ))
    else 
        printf "%4d  B/s" "$b"
    fi
}

echo "↓ $(format_rate $RX_RATE)  ↑ $(format_rate $TX_RATE)"
