#!/usr/bin/env bash
set -euo pipefail

# =========================================================
# dashboard-toggle.sh — flips the Quickshell dashboard's `enabled` gate
# (quickshell/dashboard/shell.qml) without touching the process itself.
# The dashboard is meant to stay running permanently in the background
# (workspace-emptiness tracking costs ~nothing idle -- see its own
# resource notes); this just flips whether it's allowed to actually show
# its panels, over the same "IPC call flips a property" mechanism as
# shell.qml/bar's toggleZen -- no restart, no ~140MB re-launch cost.
#
# The notification itself is sent FROM the QML side (shell.qml's
# onEnabledChanged), not here -- it's the one side that actually knows
# the resulting state without a second, possibly-desynced source of
# truth. This script only notifies on the ONE thing it alone can detect:
# the dashboard not running at all yet.
# =========================================================

if ! qs -c dashboard ipc call dashboard toggle >/dev/null 2>&1; then
    notify-send -a "Dashboard" "Dashboard" "Not running -- start it first (quickshell -c dashboard)"
    exit 1
fi
