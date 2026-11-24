#!/usr/bin/env bash
. "$(dirname "$(readlink -f "$0")")/../../../lib/hook.sh"

# Your own settings, beside wezterm.lua in the repo and ignored by git,
# linked like the other configs.
config="$REPO/config/wezterm/local.lua"
link="$HOME/.config/wezterm/local.lua"

if [[ ! -e "$config" ]]; then
    cp "$REPO/config/wezterm/local.example.lua" "$config"
    ok "local.lua created"
fi

mkdir -p "$(dirname "$link")"
if [[ -e "$link" && ! -L "$link" ]]; then
    warn "$link is a file of its own, kept: move it to $config to link it"
    exit 0
fi
ln -sfn "$config" "$link"
ok "local.lua linked"
