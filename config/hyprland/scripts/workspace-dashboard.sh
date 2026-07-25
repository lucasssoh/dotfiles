#!/usr/bin/env bash
# =========================================================
# workspace-dashboard.sh — affiche les widgets fastfetch/horloge
# (cf. dashboard-fastfetch.sh, dashboard-clock.sh, et leurs windowrules
# dans hypr/windowrules.lua) sur un workspace vide, et les masque dès
# qu'une vraie fenêtre (non flottante, non-dashboard) y apparaît.
# Réagit en direct aux événements Hyprland du workspace actif. Lancé
# en service systemd --user (cf. systemd/workspace-dashboard.service).
# =========================================================

SOCKET=""
for i in $(seq 1 30); do
    SOCKET=$(find /run/user/$(id -u)/hypr/ -name ".socket2.sock" 2>/dev/null | head -1)
    [ -n "$SOCKET" ] && break
    sleep 1
done

[ -z "$SOCKET" ] && exit 1

LOCK="/tmp/dashboard-lock"  # empêche deux lancements concurrents du dashboard

launch_dashboard() {
    [ -f "$LOCK" ] && return

    # Déjà affiché : rien à faire
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

# "Vraie" fenêtre = tuilée et non-dashboard ; sert à décider si le
# dashboard doit céder la place ou rester affiché sur ce workspace
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

# État initial (au lancement du service, avant tout événement)
update_dashboard

# Réévalue l'état du dashboard à chaque événement pouvant changer le
# contenu du workspace actif. Le sleep laisse le temps à `hyprctl clients`
# de refléter le changement avant d'être interrogé.
socat UNIX-CONNECT:"$SOCKET" STDOUT | while IFS= read -r line; do
    EVENT=$(echo "$line" | cut -d'>' -f1)

    case "$EVENT" in
        workspace|openwindow|closewindow|movewindow)
            sleep 0.1
            update_dashboard
            ;;
    esac
done
