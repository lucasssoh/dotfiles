#!/usr/bin/env bash
. "$(dirname "$(readlink -f "$0")")/../../../lib/hook.sh"

# shell-theme.json: the shell-wide look and its theme. Local to the machine,
# like bar.json: an existing file is the user's, never rewritten. The themes
# themselves ship in ~/.config/hypr/themes/.
config="$HOME/.config/hypr/shell-theme.json"
if [[ -e "$config" || -L "$config" ]]; then
    ok "existing shell-theme.json kept"
    exit 0
fi

mkdir -p "$(dirname "$config")"
cat > "$config" <<'JSON'
{
  "style": "default",
  "theme": "coucou"
}
JSON
ok "shell-theme.json written"
