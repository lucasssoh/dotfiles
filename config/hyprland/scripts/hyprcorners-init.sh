#!/usr/bin/env bash

# Récupère la résolution du monitor principal
RESOLUTION=$(hyprctl monitors -j | python3 -c "
import json, sys
monitors = json.load(sys.stdin)
main = next((m for m in monitors if m.get('focused')), monitors[0])
print(main['width'], main['height'])
")

WIDTH=$(echo "$RESOLUTION" | awk '{print $1}')
HEIGHT=$(echo "$RESOLUTION" | awk '{print $2}')

cat > ~/.config/hypr/hyprcorners.toml << TOML
timeout = 50
screen_width = $WIDTH
screen_height = $HEIGHT

[top_left]
radius = 1
dispatcher = "exec"
args = "~/.config/hypr/scripts/waybar-toggle.sh show"

[top_right]
radius = 1
dispatcher = "exec"
args = "~/.config/hypr/scripts/waybar-toggle.sh show"
TOML

# Relancer hyprcorners avec la nouvelle config
pkill hyprcorners 2>/dev/null || true
sleep 0.2
hyprcorners &
