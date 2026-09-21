#!/usr/bin/env bash
# =========================================================
# pip-daemon.sh — "picture-in-picture" mode for mpv and Satty.
#
# Listens to the Hyprland event stream: as soon as a window from the
# pip_classes list loses focus, it's shrunk and pushed into the bottom-right
# corner of the screen; as soon as it regains focus, it's restored to its
# normal size/position. No autostart: launched as needed.
#
# Only FLOATING windows can be placed this way -- a tiled window's
# geometry belongs to the layout, and both dispatchers below are no-ops
# on one. windowrules.lua's `float = true` rule for mpv is currently
# commented out, so mpv opens tiled and has to be floated (SUPER+SHIFT+SPACE)
# before PIP has anything to move.
# =========================================================

# Waits up to 30s for the Hyprland event socket to appear (useful if this
# script starts before the Hyprland session is ready).
SOCKET=""
for i in $(seq 1 30); do
    SOCKET=$(find /run/user/$(id -u)/hypr/ -name ".socket2.sock" 2>/dev/null | head -1)
    [ -n "$SOCKET" ] && break
    sleep 1
done
[ -z "$SOCKET" ] && exit 1

# Discover the focused monitor's real resolution once at startup (not
# per-event -- a monitor swap mid PIP-session is an edge case not worth
# re-querying for). Falls back to 1920x1080 if hyprctl/python3 return
# nothing usable, matching this script's previous fixed behavior.
read -r SCREEN_W SCREEN_H <<EOF_GEOM
$(hyprctl monitors -j 2>/dev/null | python3 -c "
import json, sys
try:
    mons = json.load(sys.stdin)
except Exception:
    mons = []
target = next((m for m in mons if m.get('focused')), mons[0] if mons else None)
if target:
    print(target.get('width', 1920), target.get('height', 1080))
else:
    print(1920, 1080)
" 2>/dev/null)
EOF_GEOM
SCREEN_W="${SCREEN_W:-1920}"
SCREEN_H="${SCREEN_H:-1080}"

# PIP thumbnail geometry: same proportions as the original 1920x1080-only
# constants (1/4 screen, small fixed margin from the bottom-right corner),
# now computed for whatever screen is actually focused.
PIP_MARGIN_X=20
PIP_MARGIN_Y=30
PIP_W=$(( SCREEN_W / 4 ))
PIP_H=$(( SCREEN_H / 4 ))
PIP_X=$(( SCREEN_W - PIP_W - PIP_MARGIN_X ))
PIP_Y=$(( SCREEN_H - PIP_H - PIP_MARGIN_Y ))

# Restored geometry: centered, same 2/3-of-screen proportions as before
FULL_W=$(( SCREEN_W * 2 / 3 ))
FULL_H=$(( SCREEN_H * 2 / 3 ))

# Window classes affected by PIP behavior. This array is the only place
# the list lives: it used to be repeated as a Python literal inside the
# client query below, so editing one and not the other silently kept the
# old behaviour. It is passed to that query as arguments instead.
pip_classes=("mpv" "com.gabm.satty")

# ---- Talking to the compositor -------------------------------------
# Every dispatch goes through hl.dsp.*, and that is not a style choice.
# This Hyprland is configured in Lua (hypr/*.lua), so `hyprctl dispatch`
# evaluates its argument AS LUA, and the classic syntax this script
# shipped with does not merely misbehave -- it fails to parse:
#
#   $ hyprctl dispatch movewindowpixel "exact 100 100,address:0x5..."
#   error: [string "return hl.dispatch(movewindowpixel exact 100
#          100,address:0x5...)"]:1: ')' expected near 'exact'
#
# Nothing checked that return value, so PIP has never once moved a
# window. The argument names below came from the error the call returns
# when handed an empty table, which is the fastest way to read this API:
#
#   hl.window.move: unrecognized arguments. Expected one of:
#   direction, x+y(+relative), workspace, into_group, out_of_group
#
# x/y are absolute pixels -- the `exact` of the old syntax; `relative =
# true` is the other form.
#
# ---- Resize first, THEN move ---------------------------------------
# The reverse of the order this script used, and it is not arbitrary:
# hl.dsp.window.resize keeps the window's CENTRE fixed, not its
# top-left corner. Measured, from 1920x1200 at [0,24]:
#
#   move to [1420,870] then resize to 480x300  ->  lands at [2140,1320]
#   resize to 480x300 then move to [1420,870]  ->  lands at [1420,870]
#
# 2140 is 1420 + (1920-480)/2: the shrink pushed the corner out by half
# the width it lost, off the right edge of the screen. Sizing first and
# placing second makes the last word the one that matters.
shrink_window() {
    local addr=$1
    hyprctl dispatch "hl.dsp.window.resize({ x = ${PIP_W}, y = ${PIP_H}, window = 'address:${addr}' })" >/dev/null
    hyprctl dispatch "hl.dsp.window.move({ x = ${PIP_X}, y = ${PIP_Y}, window = 'address:${addr}' })" >/dev/null
}

restore_window() {
    local addr=$1
    hyprctl dispatch "hl.dsp.window.resize({ x = ${FULL_W}, y = ${FULL_H}, window = 'address:${addr}' })" >/dev/null
    hyprctl dispatch "hl.dsp.window.move({ x = $(( (SCREEN_W - FULL_W) / 2 )), y = $(( (SCREEN_H - FULL_H) / 2 )), window = 'address:${addr}' })" >/dev/null
}

declare -A pip_state  # window address -> 0 (normal size) | 1 (shrunk to PIP)

socat -u UNIX-CONNECT:"$SOCKET" STDOUT | while IFS= read -r line; do
    EVENT=$(echo "$line" | cut -d'>' -f1)
    DATA=$(echo "$line" | sed 's/.*>>//')

    case "$EVENT" in
        activewindow)
            ACTIVE_ADDR=$(hyprctl activewindow -j | python3 -c "
import json, sys
w = json.load(sys.stdin)
print(w.get('address', ''))
" 2>/dev/null)

            # Walks through every currently open pip window
            while IFS=' ' read -r addr class; do
                [ -z "$addr" ] && continue
                if [ "$addr" = "$ACTIVE_ADDR" ]; then
                    # Active window: restore it if it was shrunk
                    if [ "${pip_state[$addr]}" = "1" ]; then
                        restore_window "$addr"
                        pip_state[$addr]=0
                    fi
                else
                    # Inactive window: shrink it if not already
                    if [ "${pip_state[$addr]}" != "1" ]; then
                        shrink_window "$addr"
                        pip_state[$addr]=1
                    fi
                fi
            done < <(hyprctl clients -j | python3 -c "
import json, sys
pip = set(sys.argv[1:])
for c in json.load(sys.stdin):
    if c.get('class') in pip:
        print(c.get('address'), c.get('class'))
" "${pip_classes[@]}")
            ;;
        closewindow)
            # Clears the state to prevent a closed address from being
            # reused by Hyprland and inherited by another window.
            #
            # The 0x is added back, and without it this never once fired.
            # The event stream and the JSON API disagree about the shape
            # of an address: socket2 emits it BARE
            #
            #   closewindow>>557b8ebbe3f0
            #
            # while `hyprctl clients -j` -- where every key in pip_state
            # comes from -- reports 0x557b8ebbe3f0. So the unset below was
            # always deleting a key that did not exist, and the stale
            # entry it was meant to remove stayed until this daemon died.
            ADDR=$(echo "$DATA" | tr -d '[:space:]')
            unset "pip_state[0x${ADDR#0x}]"
            ;;
    esac
done
