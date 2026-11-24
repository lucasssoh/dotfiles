#!/usr/bin/env bash
. "$(dirname "$(readlink -f "$0")")/../../../lib/hook.sh"

# Your own settings, beside wezterm.lua in the repo and ignored by git,
# linked like the other configs.
config="$REPO/config/wezterm/local.lua"
link="$HOME/.config/wezterm/local.lua"

if [[ ! -e "$config" ]]; then
    cat > "$config" <<'LUA'
-- Your WezTerm settings, over the author's. Any key from
-- https://wezterm.org/config/lua/config/ ; reloaded on save.
local wezterm = require 'wezterm'

return {
  -- font = wezterm.font("JetBrains Mono"),
  -- font_size = 12,
  -- window_background_opacity = 0.9,
  -- colors = { background = "#101010" },
}
LUA
    ok "local.lua created"
fi

mkdir -p "$(dirname "$link")"
if [[ -e "$link" && ! -L "$link" ]]; then
    warn "$link is a file of its own, kept: move it to $config to link it"
    exit 0
fi
ln -sfn "$config" "$link"
ok "local.lua linked"
