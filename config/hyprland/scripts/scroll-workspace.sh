#!/usr/bin/env bash
set -euo pipefail

# =========================================================
# scroll-workspace.sh {next|prev} — SUPER+wheel workspace navigation,
# bounded to the FOCUSED monitor's own assigned range instead of
# Hyprland's generic "m+1"/"m-1" relative selector (what hypr/keybinds.lua
# used to bind directly).
#
# The bug with "m+1"/"m-1": it cycles through whatever workspaces already
# EXIST on this monitor, and once it runs past the last one, just creates
# the next free GLOBAL id -- 11, 12, ... With only 1-10 ever bound to a
# keybind (keybinds.lua's own AZERTY table), a workspace born that way had
# no SUPER+key to reach it, and no SUPER+SHIFT+key to move a window back
# out of it. That's the "je me retrouve avec un 11è workspace, impossible
# d'en déplacer les fenêtres" report.
#
# Fix: read the focused monitor's ACTUAL range straight from
# `hyprctl workspacerules -j` (whatever workspace-manager.sh last set --
# 1-5/6-10 today, but this adapts automatically if that split ever
# changes, no duplicated logic here) and wrap strictly within it. Escaping
# the range becomes impossible by construction, not just unlikely.
# =========================================================

direction="${1:?usage: scroll-workspace.sh {next|prev}}"

mons_json="$(hyprctl monitors -j)"
focused_monitor="$(jq -r '.[] | select(.focused==true) | .name' <<<"$mons_json")"
[[ -z "$focused_monitor" ]] && exit 0

active="$(jq -r --arg m "$focused_monitor" '.[] | select(.name==$m) | .activeWorkspace.id // empty' <<<"$mons_json")"

# min/max workspace id currently assigned to this monitor (falls back to
# the full 1-10 span if, somehow, nothing is assigned yet).
read -r lo hi < <(hyprctl workspacerules -j | jq -r --arg m "$focused_monitor" '
    [.[] | select(.monitor==$m) | (.workspaceString | tonumber)] | sort
    | if length == 0 then "1 10" else "\(.[0]) \(.[-1])" end
')

[[ -z "$active" ]] && active=$lo

if [[ "$direction" == "next" ]]; then
    target=$(( active + 1 ))
    [[ $target -gt $hi ]] && target=$lo
else
    target=$(( active - 1 ))
    [[ $target -lt $lo ]] && target=$hi
fi

hyprctl eval "hl.dispatch(hl.dsp.focus({ workspace = \"$target\" }))" >/dev/null
