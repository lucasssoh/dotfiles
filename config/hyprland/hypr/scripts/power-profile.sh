#!/usr/bin/env bash
# power-profile.sh — follow the power source with the CPU power profile.
#
# power-profiles-daemon does NOT do this on its own, which is the usual
# misconception. Checked against the running daemon (0.30): it exposes
# `performance`, `balanced` and `power-saver`, and its only automatic
# behaviour is DEGRADING `performance` when the machine is hot or on
# battery -- it never selects `power-saver` for you. A laptop left on
# `balanced` unplugged is therefore leaving the single largest
# non-display saving on the table all day.
#
# On a Core Ultra 135H (Meteor Lake) `power-saver` pins the platform
# profile low, which is where the SoC's own power management does the
# real work -- far more than any compositor setting can. The Roue power
# wheel (waybar/scripts/performance.sh) still overrides this by hand
# whenever the user wants; this only moves the DEFAULT, and it does it on
# transitions, so a manual choice survives until the cable is next
# plugged or unplugged.
#
# Started once per session from hyprland.lua's autostart block.
# Event-driven: it blocks on udev and does nothing between transitions.

set -u
export LC_ALL=C

# Set either to "" to disable that side entirely. `power-saver` genuinely
# lowers clocks and the energy-performance preference -- that is the point
# of it -- so it is not a cosmetic setting on a machine whose stability
# depends on frequency. See the hard guard below.
PROFILE_ON_BATTERY="power-saver"
PROFILE_ON_AC="balanced"

# ---------------------------------------------------------------------------
# HARD GUARD — do not remove without reading this
# ---------------------------------------------------------------------------
# A machine with no battery gets NOTHING done to it. Not the battery
# profile, not the AC profile, not a "harmless" re-assert of the one it
# already has. It exits before powerprofilesctl is ever called.
#
# This is a safety requirement, not tidiness. The desktop-class machine
# this repo is developed on has a fault where dropping the CPU below a
# certain frequency crashes it into a reboot, so its power profile and
# governor are hand-managed and must not be touched by anything
# automatic. That machine reports an ACAD mains adapter and no BAT* at
# all, which is exactly what this guard keys on -- and it is also the
# honest definition of "this script has no business here": with no
# battery there is no battery life to optimise.
#
# Consequence: this script is inert on the development machine and only
# becomes live on the laptop it was written for. It is therefore NOT
# testable there -- verify it on the laptop, unplugged, with
# `POWER_PROFILE_DEBUG=1` and watch `powerprofilesctl get`.
has_battery() {
    local ps
    for ps in /sys/class/power_supply/*; do
        [ -r "$ps/type" ] && [ "$(cat "$ps/type")" = "Battery" ] && return 0
    done
    return 1
}

if ! has_battery; then
    exit 0
fi

# Set to 1 to get a notification on each transition. Off by default --
# the state is visible in the bar already, and a toast every time a
# charger is nudged gets old fast.
NOTIFY="${POWER_PROFILE_NOTIFY:-0}"

log() { [ -n "${POWER_PROFILE_DEBUG:-}" ] && echo "power-profile: $*" >&2; }

command -v powerprofilesctl >/dev/null 2>&1 || {
    log "powerprofilesctl absent, nothing to do"
    exit 0
}

# Same detection as idle-action.sh: the mains adapter's `online` is
# unambiguous where the battery's own `status` is not (a full battery on
# AC and a full battery discharging at 0 W read identically). Glob on the
# type because the adapter is named ACAD / AC / ADP1 depending on the
# firmware.
# The no-battery case is already handled by the hard guard above, so this
# only has to answer "is the adapter plugged in".
on_ac() {
    local ps
    for ps in /sys/class/power_supply/*; do
        [ -r "$ps/type" ] || continue
        [ "$(cat "$ps/type")" = "Mains" ] || continue
        [ -r "$ps/online" ] && [ "$(cat "$ps/online")" = "1" ] && return 0
    done
    return 1
}

apply() {
    local want
    if on_ac; then want="$PROFILE_ON_AC"; else want="$PROFILE_ON_BATTERY"; fi

    # Don't fight a profile that is already right: setting it again is
    # harmless but would stomp a deliberate manual choice every time udev
    # emits an unrelated power_supply event (they are chatty -- battery
    # capacity changes fire them too).
    local current
    current=$(powerprofilesctl get 2>/dev/null) || return 0
    [ "$current" = "$want" ] && return 0

    # A profile can be missing: `power-saver` is absent on machines whose
    # platform driver only offers two. Failing quietly is correct there.
    if powerprofilesctl set "$want" 2>/dev/null; then
        log "$current -> $want"
        [ "$NOTIFY" = "1" ] && command -v notify-send >/dev/null 2>&1 &&
            notify-send -a "power" -u low "Power profile" "$want"
    else
        log "profile '$want' unavailable"
    fi
    return 0
}

apply   # settle the profile to match the current state at session start

# udev emits on the power_supply subsystem whenever the adapter is
# plugged or unplugged. Blocking on it costs nothing between events,
# unlike polling -- which would be a poor look for a battery script.
if command -v udevadm >/dev/null 2>&1; then
    udevadm monitor --udev --subsystem-match=power_supply 2>/dev/null | while read -r _; do
        apply
    done
else
    # Fallback only: udevadm ships with systemd, so this should never run.
    while true; do
        sleep 20
        apply
    done
fi
