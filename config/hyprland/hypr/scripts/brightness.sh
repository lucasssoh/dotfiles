#!/usr/bin/env bash
# ============================================================
# brightness.sh — backlight step for the XF86MonBrightness keys
# ============================================================
# Called by hypr/keybinds.lua's XF86MonBrightnessUp/Down binds.
#
# Two jobs the bind cannot do inline:
#
#   1. A floor on the way down. brightnessctl's percent deltas are
#      relative to MAX, not to the current level, so `set 5%-` from 5%
#      subtracts 5% of max again and lands on a literal 0 -- a black
#      panel, which reads as a dead screen rather than as the dimmest
#      usable level. brightnessctl's own -n clamp has two silent traps:
#      its argument is getopt-OPTIONAL (so `-n 20` with a space does not
#      bind 20 -- the set becomes a no-op that still exits 0), and it
#      takes a RAW value, never a percentage (`-n5%` floors at 5, not at
#      5% of max). Hence: computed here, passed glued.
#
#   2. That floor is per-machine. max is 400 on asus-tuf-a15 but the
#      config is shared (hypr/hosts/), so 5% cannot be hardcoded.
#
# The OSD poke stays here too: brightnessctl has no DBus/kernel push the
# bar can react to on its own (see quickshell/bar/services/OsdState.qml),
# so the level change has to tell the bar itself.

set -u

STEP=5      # percent of max per keypress
FLOOR=5     # percent of max the Down key will not go below

case "${1:-}" in
    up|down) direction="$1" ;;
    *) echo "usage: ${0##*/} up|down" >&2; exit 2 ;;
esac

if [ "$direction" = up ]; then
    brightnessctl -q set "${STEP}%+"
else
    # Integer maths, and never a 0 floor: on a panel with a max below
    # 100 the division alone would round down to 0 and hand back exactly
    # the black screen this script exists to prevent.
    max="$(brightnessctl max 2>/dev/null)"
    floor=1
    if [ -n "$max" ] && [ "$max" -gt 0 ] 2>/dev/null; then
        floor=$(( max * FLOOR / 100 ))
        [ "$floor" -lt 1 ] && floor=1
    fi
    brightnessctl -q "-n${floor}" set "${STEP}%-"
fi

# Best effort: a missing/restarting bar must not fail the keypress.
quickshell ipc -c bar call bar pokeBrightness 2>/dev/null || true
