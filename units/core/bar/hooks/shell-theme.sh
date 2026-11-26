#!/usr/bin/env bash
. "$(dirname "$(readlink -f "$0")")/../../../lib/hook.sh"

# shell-theme.json: the shell-wide look, default or cartoon. Local to the
# machine, like bar.json: an existing file is the user's, never rewritten.
config="$HOME/.config/hypr/shell-theme.json"
if [[ -e "$config" || -L "$config" ]]; then
    ok "existing shell-theme.json kept"
    exit 0
fi

mkdir -p "$(dirname "$config")"
cat > "$config" <<'JSON'
{
  "style": "default"
}
JSON
ok "shell-theme.json written"
