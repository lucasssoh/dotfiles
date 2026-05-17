#!/usr/bin/env bash
SOCKET="/run/user/$(id -u)/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock"

launch_dashboard() {
    pkill -f "wezterm.*dashboard" 2>/dev/null
    sleep 0.2
nohup wezterm start --class "dashboard-fastfetch" -- bash ~/.config/hypr/scripts/dashboard-fastfetch.sh > /dev/null 2>&1 &
nohup wezterm start --class "dashboard-clock" -- bash ~/.config/hypr/scripts/dashboard-clock.sh > /dev/null 2>&1 &}

hide_dashboard() {
    pkill -f "wezterm.*dashboard" 2>/dev/null
}

is_workspace_empty() {
    local ws=$1
    COUNT=$(hyprctl clients -j | python3 -c "
import json, sys
clients = json.load(sys.stdin)
print(sum(1 for c in clients
    if c.get('workspace', {}).get('id') == $ws
    and 'dashboard' not in c.get('class', '')
))
")
    [ "$COUNT" -eq 0 ]
}

socat - UNIX-CONNECT:"$SOCKET" | while IFS= read -r line; do
    EVENT=$(echo "$line" | cut -d'>' -f1)
    DATA=$(echo "$line" | sed 's/.*>>//')

    case "$EVENT" in
        workspace)
            WS=$(echo "$DATA" | tr -d '[:space:]')
            if is_workspace_empty "$WS"; then
                launch_dashboard
            else
                hide_dashboard
            fi
            ;;
        openwindow)
            # DATA format: address,workspace,class,title
            CLASS=$(echo "$DATA" | cut -d',' -f3)
            echo "$CLASS" | grep -q "dashboard" && continue
            hide_dashboard
            ;;
        closewindow)
            # Vérifier si c'est une fenêtre dashboard qui se ferme
            ADDR=$(echo "$DATA" | tr -d '[:space:]')
            IS_DASH=$(hyprctl clients -j 2>/dev/null | python3 -c "
import json, sys
clients = json.load(sys.stdin)
for c in clients:
    if c.get('address','').replace('0x','') == '$ADDR':
        print('dashboard' if 'dashboard' in c.get('class','') else 'other')
        sys.exit()
print('other')
" 2>/dev/null)
            [ "$IS_DASH" = "dashboard" ] && continue
            sleep 0.3
            WS=$(hyprctl activeworkspace -j | python3 -c "
import json, sys
print(json.load(sys.stdin)['id'])
")
            if is_workspace_empty "$WS"; then
                launch_dashboard
            fi
            ;;
    esac
done
