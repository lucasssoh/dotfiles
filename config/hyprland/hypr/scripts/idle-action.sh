#!/usr/bin/env bash
# idle-action.sh — AC-aware wrapper around every hypridle action.
#
# hypridle has no notion of power source: a listener either fires or it
# doesn't. That is exactly why hypridle was switched off on the machine
# this repo grew up on -- docked to an external monitor, on mains, all
# day, a 5-minute lock and a 30-minute suspend are pure annoyance. So the
# timings stayed written in hypridle.conf and the daemon stayed disabled,
# and with it the single largest battery lever a laptop has.
#
# This puts the decision one level down instead. hypridle fires on time,
# every time; this script decides whether the action is appropriate right
# now. On mains it is a no-op, which reproduces today's behaviour exactly
# (hypridle off == nothing happens). On battery the full ladder runs.
#
# Set RUN_ON_AC below if you later want locking while docked -- it is
# deliberately the only thing standing between "no-op" and "full ladder",
# so the policy is one line to change, not a rewrite.
#
# Usage: idle-action.sh <dim|undim|lock|dpms-off|dpms-on|suspend>
# Wired from hypridle.conf; hypridle itself is started from hyprland.lua.

set -u

# Actions still performed while on mains. Empty = do nothing on AC.
# "lock dpms-off dpms-on" is the usual next step up if you want the
# screen to lock while docked; suspend is best left out of it.
RUN_ON_AC=""

# Every command below is parsed or compared, and this session is
# fr_FR.UTF-8 -- see the rest of this repo for what a localized number
# format does to shell parsing.
export LC_ALL=C

action="${1:-}"
[ -n "$action" ] || { echo "usage: $0 <dim|undim|lock|dpms-off|dpms-on|suspend>" >&2; exit 2; }

# ---------------------------------------------------------------------------
# HARD GUARD — a machine with no battery does nothing, ever
# ---------------------------------------------------------------------------
# Same guard as power-profile.sh, for the same machine. The development
# desktop has a fault where the CPU dropping below a certain frequency
# crashes it into a reboot; a suspend/resume cycle on it is not something
# to trigger from an untested timer. It reports an ACAD mains adapter and
# no BAT* at all, so keying on the battery's absence makes every action
# here provably unreachable there -- including `suspend`, which is the
# one that could not be undone.
#
# It also happens to be the honest rule: no battery, no battery life,
# nothing for an idle ladder to save.
#
# Consequence: this script is NOT testable on the development machine.
# It has to be verified on the laptop, unplugged.
for _ps in /sys/class/power_supply/*; do
    [ -r "$_ps/type" ] && [ "$(cat "$_ps/type")" = "Battery" ] && _has_battery=1
done
[ "${_has_battery:-0}" = "1" ] || exit 0

# ---------------------------------------------------------------------------
# Power source
# ---------------------------------------------------------------------------
# Read the mains adapter rather than the battery: a battery reporting
# "Full" while plugged in and one reporting "Full" while discharging at
# 0 W are indistinguishable, whereas the adapter's `online` is
# unambiguous. Glob over the type rather than hardcoding a name -- it is
# ACAD on the machine this was written on, AC on most others, ADP1 on
# some ThinkPads.
# The no-battery case is already handled by the hard guard above, so this
# only has to answer "is the adapter plugged in". A laptop whose adapter
# does not register at all reads as "on battery" here, which is the safe
# direction: the worst case is the idle ladder running while plugged in.
on_ac() {
    local ps
    for ps in /sys/class/power_supply/*; do
        [ -r "$ps/type" ] || continue
        [ "$(cat "$ps/type")" = "Mains" ] || continue
        [ -r "$ps/online" ] || continue
        [ "$(cat "$ps/online")" = "1" ] && return 0
    done
    return 1
}

if on_ac; then
    case " $RUN_ON_AC " in
        *" $action "*) ;;      # explicitly allowed on mains
        *) exit 0 ;;           # otherwise: nothing happens while plugged in
    esac
fi

# ---------------------------------------------------------------------------
# Actions
# ---------------------------------------------------------------------------
case "$action" in
    dim)
        # -s saves the current level so `brightnessctl -r` can restore
        # whatever the user had set, rather than a hardcoded value.
        brightnessctl -s set 20% >/dev/null 2>&1
        ;;
    undim)
        brightnessctl -r >/dev/null 2>&1
        ;;
    lock)
        loginctl lock-session
        ;;
    # NOT VERIFIED ON TARGET HARDWARE -- read this before trusting it.
    #
    # `hl.dsp.dpms` exists (a misspelt dispatcher name errors, this one
    # does not), but its argument shape could not be confirmed on the
    # machine this was written on: the Lua binding accepts a bogus key
    # ({ zzz = "off" }) just as happily as { state = "off" }, issuing
    # either left `hyprctl monitors -j .dpmsStatus` unchanged, and
    # debug:disable_logs defaults to true on this build so the log says
    # nothing either. Every observable channel was silent, so "it
    # returned ok" is NOT evidence that the panel turned off.
    #
    # Hence the fallback chain, most-reliable first. wlopm speaks
    # wlr-output-power-management, which is precisely this feature and
    # nothing else; it is packaged on Fedora (wlopm-1.0.0-4.fc44) but not
    # installed here. Install it on the laptop and this stops being a
    # guess:  sudo dnf install wlopm
    #
    # To verify on the target machine, from a TTY or over SSH so a failure
    # cannot strand you:
    #   ~/.config/hypr/scripts/idle-action.sh dpms-off   # panel must go dark
    #   ~/.config/hypr/scripts/idle-action.sh dpms-on
    # misc:mouse_move_enables_dpms and key_press_enables_dpms are set true
    # in hyprland.lua precisely so a failed wake is never a dead session.
    dpms-off)
        if command -v wlopm >/dev/null 2>&1; then
            wlopm --off '*' >/dev/null 2>&1
        else
            hyprctl eval 'hl.dispatch(hl.dsp.dpms({ state = "off" }))' >/dev/null 2>&1
        fi
        ;;
    dpms-on)
        if command -v wlopm >/dev/null 2>&1; then
            wlopm --on '*' >/dev/null 2>&1
        else
            hyprctl eval 'hl.dispatch(hl.dsp.dpms({ state = "on" }))' >/dev/null 2>&1
        fi
        ;;
    suspend)
        systemctl suspend
        ;;
    *)
        echo "unknown action: $action" >&2
        exit 2
        ;;
esac
