#!/usr/bin/env bash

SOCKET=""
for i in $(seq 1 30); do
    SOCKET=$(find /run/user/$(id -u)/hypr/ -name ".socket2.sock" 2>/dev/null | head -1)
    [ -n "$SOCKET" ] && break
    sleep 1
done

[ -z "$SOCKET" ] && exit 1

LOCK="/tmp/dashboard-lock"

launch_dashboard() {
    [ -f "$LOCK" ] && return

    # Déjà lancé ?
    pgrep -f "dashboard-fastfetch" >/dev/null && return

    touch "$LOCK"

    nohup wezterm start \
        --class "dashboard-fastfetch" \
        -- bash ~/.config/hypr/scripts/dashboard-fastfetch.sh \
        >/dev/null 2>&1 &

    nohup wezterm start \
        --class "dashboard-clock" \
        -- bash ~/.config/hypr/scripts/dashboard-clock.sh \
        >/dev/null 2>&1 &

    rm -f "$LOCK"
}

hide_dashboard() {
    pkill -f "dashboard-fastfetch" 2>/dev/null
    pkill -f "dashboard-clock" 2>/dev/null
}

workspace_has_real_windows() {
    local ws=$1

    hyprctl clients -j | python3 -c "
import json, sys

clients = json.load(sys.stdin)

real = [
    c for c in clients
    if c.get('workspace', {}).get('id') == $ws
    and not c.get('floating', False)
    and 'dashboard' not in c.get('class', '').lower()
]

print('yes' if real else 'no')
"
}

update_dashboard() {
    WS=$(hyprctl activeworkspace -j | python3 -c "
import json, sys
print(json.load(sys.stdin)['id'])
")

    HAS_WINDOWS=$(workspace_has_real_windows "$WS")

    if [ "$HAS_WINDOWS" = "yes" ]; then
        hide_dashboard
    else
        launch_dashboard
    fi
}

# État initial
update_dashboard

socat UNIX-CONNECT:"$SOCKET" STDOUT | while IFS= read -r line; do
    EVENT=$(echo "$line" | cut -d'>' -f1)

    case "$EVENT" in
        workspace|openwindow|closewindow|movewindow)
            sleep 0.1
            update_dashboard
            ;;
    esac
done
