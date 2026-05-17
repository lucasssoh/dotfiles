#!/usr/bin/env bash
SOCKET="/run/user/$(id -u)/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock"
LOCK="/tmp/dashboard-lock"

launch_dashboard() {
    [ -f "$LOCK" ] && return
    touch "$LOCK"
    pkill -f "wezterm.*dashboard" 2>/dev/null
    sleep 0.3
    nohup wezterm start --class "dashboard-fastfetch" -- bash ~/.config/hypr/scripts/dashboard-fastfetch.sh > /dev/null 2>&1 &
    nohup wezterm start --class "dashboard-clock" -- bash ~/.config/hypr/scripts/dashboard-clock.sh > /dev/null 2>&1 &
    rm -f "$LOCK"
}

hide_dashboard() {
    pkill -f "wezterm.*dashboard" 2>/dev/null
}

is_workspace_empty() {
    local ws=$1
    hyprctl clients -j | python3 -c "
import json, sys
clients = json.load(sys.stdin)
non_dash = [c for c in clients
    if c.get('workspace', {}).get('id') == $ws
    and 'dashboard' not in c.get('class', '')]
print('empty' if not non_dash else 'occupied')
"
}

socat - UNIX-CONNECT:"$SOCKET" | while IFS= read -r line; do
    EVENT=$(echo "$line" | cut -d'>' -f1)
    DATA=$(echo "$line" | sed 's/.*>>//')

    case "$EVENT" in
        workspace|workspacev2)
            [ "$EVENT" = "workspacev2" ] && continue
            WS=$(echo "$DATA" | tr -d '[:space:]')
            RESULT=$(is_workspace_empty "$WS")
            if [ "$RESULT" = "empty" ]; then
                launch_dashboard
            else
                hide_dashboard
            fi
            ;;
        openwindow)
            CLASS=$(echo "$DATA" | cut -d',' -f3)
            echo "$CLASS" | grep -q "dashboard" && continue
            hide_dashboard
            ;;
        closewindow)
            # Ignorer — on gère via workspace event uniquement
            ;;
    esac
done
