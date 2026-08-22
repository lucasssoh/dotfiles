#!/usr/bin/env bash
set -euo pipefail

# =========================================================
# compact-workspaces.sh — packs occupied workspaces toward the start of
# their range, PER MONITOR (never mixing internal/external: each monitor
# only compacts within its own workspaces, as assigned by
# workspace-manager.sh).
#
# E.g. (main screen, 1-5): 2, 3, 4 occupied -> compacted into 1, 2, 3.
#
# MANUAL trigger only (keybind): this Hyprland build exposes a Lua API
# (hl.dsp.window.move) that offers no silent equivalent to
# movetoworkspacesilent — every move makes the screen jump to the target
# workspace. The script closes the loop by refocusing each monitor on its
# original content (renumbered if needed) once all moves are done.
# =========================================================

rules_json="$(hyprctl workspacerules -j)"
clients_json="$(hyprctl clients -j)"
monitors_json="$(hyprctl monitors -j)"

focused_monitor="$(jq -r '.[] | select(.focused==true) | .name' <<<"$monitors_json")"

move_window() {
    local addr="$1" target="$2"
    hyprctl eval "hl.dispatch(hl.dsp.window.move({ window = \"address:$addr\", workspace = \"$target\" }))" >/dev/null
}

refocus() {
    local ws="$1"
    hyprctl eval "hl.dispatch(hl.dsp.focus({ workspace = \"$ws\" }))" >/dev/null
}

mapfile -t monitor_names < <(jq -r '.[].name' <<<"$monitors_json")

declare -A restore_focus  # monitor -> workspace to refocus at the end of the script
declare -A moved          # monitor -> non-empty iff a window actually moved on it

for mon in "${monitor_names[@]}"; do
    mapfile -t slots < <(jq -r --arg m "$mon" \
        '[.[] | select(.monitor==$m) | (.workspaceString|tonumber)] | sort | .[]' <<<"$rules_json")
    [[ ${#slots[@]} -eq 0 ]] && continue

    slots_json="$(printf '%s\n' "${slots[@]}" | jq -R 'tonumber' | jq -s '.')"

    active_ws="$(jq -r --arg m "$mon" '.[] | select(.name==$m) | .activeWorkspace.id // empty' <<<"$monitors_json")"
    [[ -n "$active_ws" ]] && restore_focus["$mon"]="$active_ws"

    # Occupied workspaces (real windows, excluding the empty dashboard)
    # among this monitor's slots, in ascending slot order
    mapfile -t occ < <(jq -r --argjson slots "$slots_json" '
        ([.[] | select(.class | ascii_downcase | contains("dashboard") | not) | .workspace.id] | unique) as $busy
        | $slots[] | select(. as $s | $busy | index($s))
    ' <<<"$clients_json")

    for i in "${!occ[@]}"; do
        old="${occ[$i]}"
        new="${slots[$i]}"
        [[ "$old" == "$new" ]] && continue

        while IFS= read -r addr; do
            [[ -z "$addr" ]] && continue
            move_window "$addr" "$new"
        done < <(jq -r --argjson ws "$old" \
            '.[] | select(.workspace.id==$ws and (.class | ascii_downcase | contains("dashboard") | not)) | .address' \
            <<<"$clients_json")

        moved["$mon"]=1
        if [[ "${restore_focus[$mon]:-}" == "$old" ]]; then
            restore_focus["$mon"]="$new"
        fi
    done
done

# Refocuses each monitor whose content actually got renumbered, back onto
# it (a move forces Hyprland to jump the screen to the destination
# workspace as a side effect -- see header comment). Monitors where
# nothing moved are left alone: unconditionally refocusing every monitor
# here, even ones that were already fully packed, was itself dispatching
# `hl.dsp.focus({workspace=<already-active>})` on them for no reason --
# which reasserts focus onto that workspace's *last-focused* window, not
# necessarily whichever window/pane you actually had selected right then.
# That's what made SUPER+C feel like it was still "doing something"
# (windows/focus visibly resettling) even when there was nothing left to
# compact. The monitor that had keyboard focus initially is refocused
# last, to give it back to it.
for mon in "${monitor_names[@]}"; do
    [[ -z "${moved[$mon]:-}" ]] && continue
    [[ "$mon" == "$focused_monitor" ]] && continue
    [[ -n "${restore_focus[$mon]:-}" ]] && refocus "${restore_focus[$mon]}"
done
[[ -n "${moved[$focused_monitor]:-}" && -n "${restore_focus[$focused_monitor]:-}" ]] && refocus "${restore_focus[$focused_monitor]}"

# The hl.dsp.window.move()/hl.dsp.focus() calls above (via move_window/
# refocus) don't emit anything on Hyprland's normal IPC event socket --
# same "non-legacy parser" quirk noted throughout this repo (hdr.sh,
# quickshell/bar/modules/Hdr.qml) -- so Quickshell's own workspace/
# toplevel cache goes stale after a compact: it keeps showing windows in
# their pre-compact slots until something else happens to refresh it.
# Nudge it directly. Silently a no-op if quickshell isn't running/
# installed (still using waybar, or between sessions).
qs -c bar ipc call bar refreshWorkspaces >/dev/null 2>&1 || true
