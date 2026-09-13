#!/usr/bin/env bash
# battery-probe.sh — measure real system power draw, for A/B testing settings.
#
# Why this exists: every "make Hyprland lighter" list on the internet is
# folklore, and this repo has already been burnt by it once. On the RTX
# 4060 machine, quadrupling the shadow (range 50 -> 200, i.e. four times
# the blur skirt around every window) moved GPU load by 0.9 points
# against a +-0.5 point noise floor -- indistinguishable from turning
# shadows off entirely. The "obvious" optimisation of shrinking the
# shadow would have degraded the look for nothing.
#
# That measurement does NOT transfer to the IdeaPad Slim 5 14IMH10. A
# Core Ultra 135H drives an Arc Xe-LPG iGPU that shares its power budget
# AND its memory bandwidth with the CPU cores, on a ~15-28 W package
# instead of a desktop-class dGPU. Fill-rate effects may well cost real
# battery there. May. The point of this script is to find out instead of
# assuming -- in either direction.
#
# What it measures: the battery's own reported draw, in watts. That is
# the whole machine -- panel, SoC, RAM, wifi -- which is exactly what
# battery life depends on, and is strictly better than a GPU utilisation
# percentage for this purpose. It needs the laptop to be ON BATTERY:
# plugged in, the battery reports charge current, not system draw.
#
# RAPL (/sys/class/powercap/intel-rapl/.../energy_uj) would give the
# package alone, but it is mode 0400 root-only since the Platypus
# side-channel mitigation, and it misses the panel, which on a 14" laptop
# is a large share of idle draw. The battery gauge needs no privileges
# and sees everything.
#
# Usage:
#   battery-probe.sh 30                  measure for 30 s, print watts
#   battery-probe.sh 30 "label"          same, with a label in the output
#
# Typical A/B session on the new laptop, unplugged, screen at a fixed
# brightness, nothing else running:
#   battery-probe.sh 60 "shadow on"
#   hyprctl eval 'hl.config({ decoration = { shadow = { enabled = false } } })'
#   battery-probe.sh 60 "shadow off"
#   hyprctl reload            # back to the config's real values
# Run each side twice and interleave them. If the two runs of the SAME
# setting differ by as much as the two settings do, the effect is noise
# and the setting is not worth changing -- that is the whole lesson from
# the shadow measurement above.

set -u
export LC_ALL=C

DURATION="${1:-30}"
LABEL="${2:-}"

case "$DURATION" in
    ''|*[!0-9]*) echo "usage: $0 <seconds> [label]" >&2; exit 2 ;;
esac

# ---------------------------------------------------------------------------
# Find the battery
# ---------------------------------------------------------------------------
BAT=""
for ps in /sys/class/power_supply/*; do
    [ -r "$ps/type" ] || continue
    [ "$(cat "$ps/type")" = "Battery" ] || continue
    BAT="$ps"
    break
done

if [ -z "$BAT" ]; then
    echo "No battery found under /sys/class/power_supply." >&2
    echo "This script only means anything on a laptop running on battery." >&2
    exit 1
fi

status=$(cat "$BAT/status" 2>/dev/null || echo Unknown)
if [ "$status" != "Discharging" ]; then
    echo "Battery status is '$status', not 'Discharging'." >&2
    echo "Unplug the charger: on AC the gauge reports charge current, not system draw." >&2
    exit 1
fi

# ---------------------------------------------------------------------------
# Read instantaneous power
# ---------------------------------------------------------------------------
# Two sysfs dialects: energy-based gauges expose power_now in uW directly,
# charge-based ones expose current_now (uA) and voltage_now (uV) and leave
# the multiplication to us. Most Intel laptops are the first kind; enough
# are the second that assuming would break on the machine that matters.
read_watts() {
    if [ -r "$BAT/power_now" ]; then
        awk '{printf "%.3f", $1 / 1000000}' "$BAT/power_now"
    elif [ -r "$BAT/current_now" ] && [ -r "$BAT/voltage_now" ]; then
        local i v
        i=$(cat "$BAT/current_now")
        v=$(cat "$BAT/voltage_now")
        awk -v i="$i" -v v="$v" 'BEGIN{printf "%.3f", (i/1000000) * (v/1000000)}'
    else
        echo ""
    fi
}

probe=$(read_watts)
if [ -z "$probe" ]; then
    echo "Battery at $BAT exposes neither power_now nor current_now+voltage_now." >&2
    exit 1
fi

# ---------------------------------------------------------------------------
# Sample
# ---------------------------------------------------------------------------
# The gauge updates on its own schedule (often ~1 Hz, sometimes slower),
# so sampling faster than 1 s buys repeated identical readings, not
# precision. The first two seconds are dropped: switching a Hyprland
# setting causes a burst of re-rendering that is not the steady state
# being measured.
[ -n "$LABEL" ] && printf '%s: ' "$LABEL"
printf 'sampling %ss' "$DURATION"

sleep 2
samples=""
n=0
while [ "$n" -lt "$DURATION" ]; do
    w=$(read_watts)
    samples="$samples $w"
    n=$((n + 1))
    printf '.'
    sleep 1
done
printf '\n'

echo "$samples" | awk '{
    n = 0; sum = 0; min = 1e9; max = 0
    for (i = 1; i <= NF; i++) {
        v = $i + 0
        if (v <= 0) continue          # gauge hiccup, not a real reading
        n++; sum += v
        if (v < min) min = v
        if (v > max) max = v
    }
    if (n == 0) { print "  no valid samples"; exit 1 }
    mean = sum / n
    ss = 0
    for (i = 1; i <= NF; i++) { v = $i + 0; if (v > 0) ss += (v - mean) ^ 2 }
    sd = (n > 1) ? sqrt(ss / (n - 1)) : 0
    printf "  mean %.2f W   sd %.2f   min %.2f   max %.2f   (%d samples)\n", mean, sd, min, max, n
    printf "  -> a difference smaller than about %.2f W between two settings is noise\n", 2 * sd
}'
