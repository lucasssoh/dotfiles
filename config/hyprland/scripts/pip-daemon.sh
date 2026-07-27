#!/usr/bin/env bash
# =========================================================
# pip-daemon.sh — "picture-in-picture" mode for mpv and Satty.
#
# Listens to the Hyprland event stream: as soon as a window from the
# pip_classes list loses focus, it's shrunk and pushed into the bottom-right
# corner of the screen; as soon as it regains focus, it's restored to its
# normal size/position. No autostart: launched as needed.
# =========================================================

# Waits up to 30s for the Hyprland event socket to appear (useful if this
# script starts before the Hyprland session is ready).
SOCKET=""
for i in $(seq 1 30); do
    SOCKET=$(find /run/user/$(id -u)/hypr/ -name ".socket2.sock" 2>/dev/null | head -1)
    [ -n "$SOCKET" ] && break
    sleep 1
done
[ -z "$SOCKET" ] && exit 1

# PIP thumbnail geometry (bottom-right corner of a 1920x1080 screen)
PIP_W=480
PIP_H=270
PIP_X=1420
PIP_Y=780

# Restored geometry (centered on a 1920x1080 screen)
FULL_W=1280
FULL_H=720

# Window classes affected by PIP behavior
pip_classes=("mpv" "com.gabm.satty")

is_pip_class() {
    local class=$1
    for c in "${pip_classes[@]}"; do
        [ "$c" = "$class" ] && return 0
    done
    return 1
}

shrink_window() {
    local addr=$1
    hyprctl dispatch movewindowpixel "exact ${PIP_X} ${PIP_Y},address:${addr}"
    hyprctl dispatch resizewindowpixel "exact ${PIP_W} ${PIP_H},address:${addr}"
}

restore_window() {
    local addr=$1
    hyprctl dispatch movewindowpixel "exact $(( (1920 - FULL_W) / 2 )) $(( (1080 - FULL_H) / 2 )),address:${addr}"
    hyprctl dispatch resizewindowpixel "exact ${FULL_W} ${FULL_H},address:${addr}"
}

declare -A pip_state  # window address -> 0 (normal size) | 1 (shrunk to PIP)

socat -u UNIX-CONNECT:"$SOCKET" STDOUT | while IFS= read -r line; do
    EVENT=$(echo "$line" | cut -d'>' -f1)
    DATA=$(echo "$line" | sed 's/.*>>//')

    case "$EVENT" in
        activewindow)
            ACTIVE_CLASS=$(echo "$DATA" | cut -d',' -f1)
            ACTIVE_ADDR=$(hyprctl activewindow -j | python3 -c "
import json, sys
w = json.load(sys.stdin)
print(w.get('address', ''))
" 2>/dev/null)

            # Walks through every currently open pip window
            while IFS=' ' read -r addr class; do
                [ -z "$addr" ] && continue
                if [ "$addr" = "$ACTIVE_ADDR" ]; then
                    # Active window: restore it if it was shrunk
                    if [ "${pip_state[$addr]}" = "1" ]; then
                        restore_window "$addr"
                        pip_state[$addr]=0
                    fi
                else
                    # Inactive window: shrink it if not already
                    if [ "${pip_state[$addr]}" != "1" ]; then
                        shrink_window "$addr"
                        pip_state[$addr]=1
                    fi
                fi
            done < <(hyprctl clients -j | python3 -c "
import json, sys
clients = json.load(sys.stdin)
pip = ['mpv', 'com.gabm.satty']
for c in clients:
    if c.get('class') in pip:
        print(c.get('address'), c.get('class'))
")
            ;;
        closewindow)
            # Clears the state to prevent a closed address from being
            # reused by Hyprland and inherited by another window
            ADDR=$(echo "$DATA" | tr -d '[:space:]')
            unset "pip_state[$ADDR]"
            ;;
    esac
done
