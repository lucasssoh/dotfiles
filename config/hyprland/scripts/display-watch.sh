#!/usr/bin/env bash
# display-watch.sh — applies the screen files as soon as they are saved.
#
# Watches ~/.config/hypr with inotify (no polling: the process sleeps in
# read() until the kernel reports a write) for:
#   scale.json           the scale of each screen
#   monitor-layout.json  where the screens sit
#   display-layout.json  which screens are on, and the main one
#   hdr-state.json       HDR or SDR, per screen
# and runs workspace-manager.sh, the one engine that turns them into
# monitor rules. It recomputes every screen, and Hyprland applies only the
# fields that differ, so each file gets its own reaction: a new position
# moves the screens, a new scale rescales, and only an HDR change or a
# screen turned on/off goes through a modeset.
#
# Started once per session by hypr/hyprland.lua.

set -uo pipefail

dir="$HOME/.config/hypr"
engine="$HOME/.config/hypr/scripts/workspace-manager.sh"

# One watcher per session.
exec 9>"${XDG_RUNTIME_DIR:-/tmp}/coucou-display-watch.lock"
flock -n 9 || exit 0

# close_write: written in place. moved_to: written beside, then renamed
# (nvim, jq + mv). delete: removed, back to the defaults.
inotifywait -m -q -e close_write,moved_to,delete --format '%f' "$dir" 9>&- |
    while read -r name; do
        case "$name" in
            scale.json|monitor-layout.json|display-layout.json|hdr-state.json) ;;
            *) continue ;;
        esac
        # One run per save: an editor's save, or a script writing two of
        # these files, comes as a burst of events. Swallow it until 250 ms
        # pass without one (a read timeout, still no polling).
        while read -r -t 0.25 _; do :; done
        bash "$engine" 9>&-
    done
