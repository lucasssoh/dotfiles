#!/usr/bin/env bash

SOCKET=""
for i in $(seq 1 30); do
    SOCKET=$(find /run/user/$(id -u)/hypr/ -name ".socket2.sock" 2>/dev/null | head -1)
    [ -n "$SOCKET" ] && break
    sleep 1
done
[ -z "$SOCKET" ] && exit 1

PIP_W=480
PIP_H=270
PIP_X=1420
PIP_Y=780

FULL_W=1280
FULL_H=720

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
declare -A pip_state  # addr -> 0 (normal) | 1 (pip)

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

            # Parcourir toutes les fenêtres pip
            while IFS=' ' read -r addr class; do
                [ -z "$addr" ] && continue
                if [ "$addr" = "$ACTIVE_ADDR" ]; then
                    # C'est la fenêtre active → restaurer
                    if [ "${pip_state[$addr]}" = "1" ]; then
                        restore_window "$addr"
                        pip_state[$addr]=0
                    fi
                else
                    # Pas active → shrink
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
            ADDR=$(echo "$DATA" | tr -d '[:space:]')
            unset "pip_state[$ADDR]"
            ;;
    esac
done
