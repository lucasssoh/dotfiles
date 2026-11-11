#!/usr/bin/env bash
. "$(dirname "$(readlink -f "$0")")/../../../lib/hook.sh"

config="$REPO/config/hyprland/hypr/bar-position.json"
if [[ -e "$config" || -L "$config" ]]; then
    ok "bar position preserved"
    exit 0
fi

printf '{\n  "position": "top"\n}\n' > "$config"
ok "bar position initialized"
