#!/usr/bin/env bash
# idle-action.sh — the single place that decides whether an idle action
# should actually happen right now.
#
# hypridle has no notion of power source or of which machine it is running
# on: a listener either fires or it doesn't. That is why this daemon spent
# so long simply switched off -- docked to an external monitor, on mains,
# all day, a 5-minute lock and a 30-minute suspend are pure annoyance, so
# the timings stayed written in hypridle.conf and the daemon stayed dead,
# and with it the single largest battery lever a laptop has.
#
# The decision lives one level down instead. hypridle fires on time, every
# time; this script answers "is that appropriate, here, now?" against four
# gates, in this order:
#
#   1. Restore actions (undim, dpms-on) bypass everything. A screen must
#      never stay dim or dark because of a policy decision -- see below.
#   2. The host profile's IDLE_ENABLED (hosts/<machine>.env, resolved by
#      host-profile.sh). This is machine identity: the development desktop
#      says no by name.
#   3. IDLE_REQUIRE_BATTERY, the original capability guard: no battery, no
#      battery life to save, nothing to do.
#   4. The ladder tag, --on ac | --on battery. hypridle.conf carries BOTH
#      ladders at once and each rung declares which power source it is
#      for; the rungs of the other one no-op here. That is what lets the
#      laptop lock at 5 minutes unplugged and 15 minutes plugged in from a
#      single conf, with no daemon restart when the cable moves.
#
# Usage: idle-action.sh <dim|undim|lock|dpms-off|dpms-on|suspend|
#                        sleep|resume> [--on ac|battery] [--dry-run]
#
# sleep/resume are hypridle's before_sleep_cmd/after_sleep_cmd -- see the
# wake submap below for why they are not just lock-session/dpms-on.
#
# --dry-run prints the verdict instead of acting, which is the only way to
# exercise the laptop's policy on a machine where it must never run:
#
#   HOST_PROFILE=default ./idle-action.sh lock --on ac --dry-run
#
# Wired from hypridle.conf; hypridle itself is started from hyprland.lua.

set -u

# Every command below is parsed or compared, and this session is
# fr_FR.UTF-8 -- see the rest of this repo for what a localized number
# format does to shell parsing.
export LC_ALL=C

# ---------------------------------------------------------------------------
# Arguments
# ---------------------------------------------------------------------------
action=""
ladder=""        # "" = this rung applies to any power source
dry_run=0

while [ $# -gt 0 ]; do
    case "$1" in
        --on)      ladder="${2:-}"; shift 2 || true ;;
        --dry-run) dry_run=1; shift ;;
        -*)        echo "unknown option: $1" >&2; exit 2 ;;
        *)         action="$1"; shift ;;
    esac
done

[ -n "$action" ] || {
    echo "usage: $0 <dim|undim|lock|dpms-off|dpms-on|suspend|sleep|resume> [--on ac|battery] [--dry-run]" >&2
    exit 2
}

case "$ladder" in
    ""|ac|battery) ;;
    *) echo "--on takes 'ac' or 'battery', got '$ladder'" >&2; exit 2 ;;
esac

# How far `dim` pulls the backlight down, as a percentage OF THE CURRENT
# level -- 40 means "keep 40% of whatever is on screen now". Deliberately
# not a percentage of the panel's maximum: see the dim action below for
# what that cost. Raise it for a gentler dim, lower it for a starker one.
DIM_PERCENT=40

# Seconds after an IDLE lock during which any key, or a mouse move of
# more than 5px, unlocks without a password (hyprlock --grace). The "I
# was right here, I just stopped moving" case. Only the idle lock gets
# it: Super+Escape and the pre-suspend lock (hypridle's lock_cmd) run
# hyprlock bare -- a grace there would mean opening the lid and nudging
# the mouse unlocks a machine that has been asleep for hours.
LOCK_GRACE=5

# The wake submap (keybinds.lua): while it is active, the next key only
# leaves it -- nothing gets typed. Entered whenever the panel goes dark,
# so the key that wakes the screen does not land in hyprlock's password
# field (Hyprland delivers the dpms-waking key to the focused surface).
wake_submap() {
    hyprctl eval "hl.dispatch(hl.dsp.submap(\"$1\"))" >/dev/null 2>&1
}

verdict() {
    [ "$dry_run" = 1 ] && echo "$action: $1"
    return 0
}

# ---------------------------------------------------------------------------
# GATE 1 — restore actions are never gated
# ---------------------------------------------------------------------------
# undim and dpms-on run unconditionally, before any profile or power check.
#
# This is a correctness requirement, not leniency. The gates below all
# depend on the CURRENT state, and the state can change while the machine
# is idle: dim at 2m30 on battery, plug the charger in at 3m, and a
# power-filtered `undim` on resume would decide it belongs to the other
# ladder and leave the panel at 20% brightness with no way to explain it.
# The same applies to dpms-on, which general{}'s after_sleep_cmd relies on
# to bring the panel back after a suspend.
#
# Both are idempotent and safe to run when nothing dimmed anything:
# `brightnessctl -r` with no saved level does nothing, `wlopm --on` on an
# already-on output does nothing.
#
# sleep/resume are ungated for the same reason plus one: they are what
# hypridle runs around EVERY suspend, idle or manual, on every machine --
# the lock before sleep must never depend on the idle policy.
case "$action" in
    undim|dpms-on|sleep|resume) ;;
    *)
        # ── GATE 2 — this machine, by name ──────────────────────────────
        # shellcheck source=host-profile.sh
        . "$(dirname "$0")/host-profile.sh"
        host_profile_load

        if [ "${IDLE_ENABLED:-1}" != "1" ]; then
            verdict "skipped (IDLE_ENABLED=0 in profile ${HOST_PROFILE_ID:-?})"
            exit 0
        fi

        # ── GATE 3 — capability: no battery, nothing to save ────────────
        # Kept from the original version of this script and still the
        # last line of defence: even a mis-resolved profile cannot make a
        # batteryless machine suspend itself.
        if [ "${IDLE_REQUIRE_BATTERY:-1}" = "1" ]; then
            has_battery=0
            for _ps in /sys/class/power_supply/*; do
                [ -r "$_ps/type" ] || continue
                [ "$(cat "$_ps/type")" = "Battery" ] && has_battery=1
            done
            if [ "$has_battery" = 0 ]; then
                verdict "skipped (no battery on this machine)"
                exit 0
            fi
        fi

        # ── Policy: is this action permitted here at all? ───────────────
        case " ${IDLE_ALLOW:-} " in
            *" $action "*) ;;
            *) verdict "skipped (not in IDLE_ALLOW)"; exit 0 ;;
        esac

        # ── GATE 4 — the ladder this rung belongs to ────────────────────
        # Read the mains adapter rather than the battery: a battery
        # reporting "Full" while plugged in and one reporting "Full" while
        # discharging at 0 W are indistinguishable, whereas the adapter's
        # `online` is unambiguous. Glob over the type rather than
        # hardcoding a name -- it is ACAD on the machine this was written
        # on, AC on most others, ADP1 on some ThinkPads.
        #
        # A laptop whose adapter does not register at all reads as "on
        # battery", which is the safe direction: the worst case is the
        # idle ladder running while plugged in, never a machine that
        # refuses to lock.
        if [ -n "$ladder" ]; then
            on_ac=0
            for _ps in /sys/class/power_supply/*; do
                [ -r "$_ps/type" ] || continue
                [ "$(cat "$_ps/type")" = "Mains" ] || continue
                [ -r "$_ps/online" ] || continue
                [ "$(cat "$_ps/online")" = "1" ] && on_ac=1
            done

            [ "$on_ac" = 1 ] && now="ac" || now="battery"
            if [ "$ladder" != "$now" ]; then
                verdict "skipped (rung is --on $ladder, machine is on $now)"
                exit 0
            fi
        fi
        ;;
esac

if [ "$dry_run" = 1 ]; then
    echo "$action: would run"
    exit 0
fi

# ---------------------------------------------------------------------------
# Actions
# ---------------------------------------------------------------------------
case "$action" in
    dim)
        # -s saves the current level so `brightnessctl -r` can restore
        # whatever the user had set, rather than a hardcoded value.
        #
        # RELATIVE to the current level, not an absolute one. This used to
        # be `set 20%`, which brightnessctl reads as 20% OF MAX -- a fixed
        # 80/400 on this panel whatever the screen was actually showing.
        # That is not a dim, it is "jump to one specific brightness", and
        # at any working level below 20% it is an UNDIM: measured on this
        # machine at its normal 20/400 (5%), `idle-action.sh dim` took the
        # panel to 80 -- four times BRIGHTER -- as the screen's way of
        # announcing you had stopped typing.
        #
        # `set N%-` is not the fix either: brightnessctl subtracts N% of
        # MAX there too, so from 100/400 a `40%-` lands on 0, i.e. a black
        # panel. Both of its percent forms are max-relative; only
        # arithmetic on `get` is current-relative, hence the shell maths.
        #
        # Two clamps, and both earn their place:
        #   floor  -- 1% of max, so a dim from an already-low level stays
        #             visible instead of reaching 0 and reading as a
        #             failed screen.
        #   ceiling -- never above the current level, because at 1-2%
        #             brightness the floor itself would otherwise be a
        #             brightening. Below the floor there is simply nothing
        #             left to dim, and the rung becomes a no-op.
        dim_cur="$(brightnessctl get 2>/dev/null)"
        dim_max="$(brightnessctl max 2>/dev/null)"
        if [ -n "$dim_cur" ] && [ -n "$dim_max" ] && [ "$dim_max" -gt 0 ] 2>/dev/null; then
            dim_target=$(( dim_cur * DIM_PERCENT / 100 ))
            dim_floor=$(( dim_max / 100 ))
            [ "$dim_floor" -lt 1 ] && dim_floor=1
            [ "$dim_target" -lt "$dim_floor" ] && dim_target="$dim_floor"
            [ "$dim_target" -gt "$dim_cur" ] && dim_target="$dim_cur"
            brightnessctl -s set "$dim_target" >/dev/null 2>&1
        else
            # brightnessctl could not report a level (no backlight device).
            # Saving and restoring still works, so keep the old absolute
            # behaviour rather than skipping the rung entirely.
            brightnessctl -s set 20% >/dev/null 2>&1
        fi
        ;;
    undim)
        brightnessctl -r >/dev/null 2>&1
        ;;
    lock)
        # hyprlock directly rather than `loginctl lock-session`: the
        # latter goes through hypridle's lock_cmd, which is shared with
        # the pre-suspend lock and so must stay grace-free.
        pidof hyprlock >/dev/null || exec hyprlock --grace "$LOCK_GRACE"
        ;;
    # VERIFIED on the IdeaPad Slim 5 14IMH10 (eDP-1), via the wlopm branch.
    # `hyprctl monitors -j .dpmsStatus` went true -> false -> true across
    # dpms-off/dpms-on, which is the observable channel that stayed stubbornly
    # silent on the machine this was originally written on and is why the
    # block below used to open with "NOT VERIFIED ON TARGET HARDWARE".
    #
    # The DISPATCHER fallback is still unverified, and the original warning
    # stands for it: `hl.dsp.dpms` exists (a misspelt dispatcher name errors,
    # this one does not), but its argument shape could never be confirmed --
    # the Lua binding accepts a bogus key ({ zzz = "off" }) just as happily as
    # { state = "off" }, issuing either left .dpmsStatus unchanged, and
    # debug:disable_logs defaults to true on this build so the log says
    # nothing either. Every observable channel was silent there, so "it
    # returned ok" is NOT evidence that the panel turned off. It remains a
    # last resort for a machine without wlopm, not a tested path.
    #
    # So keep wlopm installed: it speaks wlr-output-power-management, which is
    # precisely this feature and nothing else, and it is the only branch of
    # this chain anyone has ever actually watched work. It is declared in
    # config/hyprland/install.sh; if it goes missing this silently degrades to
    # the guess above.
    #
    # To re-verify after a Hyprland or wlopm upgrade, from a TTY or over SSH
    # so a failure cannot strand you:
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
        wake_submap wake
        ;;
    # resume is after_sleep_cmd: panel on, but the submap stays armed.
    # That hook runs as the machine wakes, and the key that woke it may
    # arrive after it -- disarming here would let that key through. So the
    # first key after a suspend always only wakes, even when opening the
    # lid already lit the panel.
    dpms-on|resume)
        if command -v wlopm >/dev/null 2>&1; then
            wlopm --on '*' >/dev/null 2>&1
        else
            hyprctl eval 'hl.dispatch(hl.dsp.dpms({ state = "on" }))' >/dev/null 2>&1
        fi
        # Only when this is a wake from the dpms-off rung (hypridle's
        # on-resume): if a KEY did the waking, the submap already swallowed
        # it and left; if the mouse did, leaving here is what hands the
        # keyboard back. Not reached from after_sleep_cmd -- see resume.
        [ "$action" = dpms-on ] && wake_submap reset
        ;;
    # before_sleep_cmd. Arm the wake submap BEFORE locking, so the key that
    # wakes the machine cannot race hyprlock's first frame into the field.
    sleep)
        wake_submap wake
        loginctl lock-session
        ;;
    suspend)
        systemctl suspend
        ;;
    *)
        echo "unknown action: $action" >&2
        exit 2
        ;;
esac
