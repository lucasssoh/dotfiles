#!/usr/bin/env bash
. "$(dirname "$(readlink -f "$0")")/../../../lib/hook.sh"

config="$REPO/config/hyprland/hypr/bar-island.json"
if [[ -e "$config" || -L "$config" ]]; then
    ok "existing island look kept"
    exit 0
fi

cat > "$config" <<'JSON'
{
  "mode": "dynamic",
  "background": "#2c2c2e",
  "opacity": 0.2,
  "blur": false,
  "text": "#f2f2f7"
}
JSON
ok "default island look set"
