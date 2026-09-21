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
#      config is shared (hypr/hosts/), so a raw floor cannot be
#      hardcoded -- it has to be a fraction of the panel's own max.
#      That fraction is expressed in PER MILLE, not percent, because
#      the wanted floor here is 10/400 = 2.5% and this is integer
#      shell arithmetic: `max * 2 / 100` would floor at 8, `max * 3 /
#      100` at 12, and neither is the level that was asked for.
#
#      Note this is a rapport-cyclique fraction, not a luminance one.
#      /sys/class/backlight/intel_backlight/scale reads `unknown` and
#      type is `raw`, so the kernel itself makes no claim that these
#      400 steps map linearly to nits -- 200 is not "half the nits of
#      400". Treat the numbers as PWM duty, never as brightness units.
#
# The OSD poke stays here too: brightnessctl has no DBus/kernel push the
# bar can react to on its own (see quickshell/bar/services/OsdState.qml),
# so the level change has to tell the bar itself.

set -u

STEP=5           # percent of max per keypress
FLOOR_PERMILLE=25  # per mille of max the Down key will not go below

case "${1:-}" in
    up|down) direction="$1" ;;
    *) echo "usage: ${0##*/} up|down" >&2; exit 2 ;;
esac

if [ "$direction" = up ]; then
    brightnessctl -q set "${STEP}%+"
else
    # Integer maths, and never a 0 floor: on a panel with a max below
    # 1000 the division alone would round down to 0 and hand back exactly
    # the black screen this script exists to prevent.
    max="$(brightnessctl max 2>/dev/null)"
    floor=1
    if [ -n "$max" ] && [ "$max" -gt 0 ] 2>/dev/null; then
        floor=$(( max * FLOOR_PERMILLE / 1000 ))
        [ "$floor" -lt 1 ] && floor=1
    fi
    brightnessctl -q "-n${floor}" set "${STEP}%-"
fi

# Best effort: a missing/restarting bar must not fail the keypress.
quickshell ipc -c bar call bar pokeBrightness 2>/dev/null || true
