#!/usr/bin/env bash
# host-profile.sh — resolve which machine this is, and load its knobs.
#
# ── Why this exists ─────────────────────────────────────────────────────
# Until now the only way this repo told its machines apart was a proxy:
# "does /sys/class/power_supply contain a Battery?". idle-action.sh and
# power-profile.sh both key on it, and on the machine this repo is
# developed on -- an ASUS TUF Gaming A15 whose battery does not register
# at all -- that proxy happens to give the right answer, so both scripts
# are inert here.
#
# It gives the right answer by accident, and it has two failure modes:
#
#   * It is not stable. Put a working battery back in the TUF and every
#     guard silently disarms at once -- including power-profile.sh's,
#     which exists because this machine reboots when its CPU drops below
#     a certain frequency. A safety guard that a hardware repair can
#     switch off is not a guard.
#   * It cannot express policy. "Lock after 15 minutes on mains on the
#     laptop, never on the TUF" is not a statement about batteries, and
#     no amount of power_supply probing will encode it.
#
# So: capability detection stays where the question really is about a
# capability (see IDLE_REQUIRE_BATTERY below, which is still enforced),
# and machine identity gets its own layer here, for the questions that
# really are about which machine this is.
#
# ── The rule: name the exception, not the norm ──────────────────────────
# hosts/default.env holds the behaviour a normal laptop should have.
# hosts/<id>.env holds only what a specific machine does DIFFERENTLY, and
# is sourced on top. A machine with no entry of its own therefore gets
# the sane default -- which is the whole point: a new laptop clones this
# repo and behaves correctly with no file written for it, exactly the way
# scripts/lib/hardware.sh classifies a CPU released after it was last
# edited. Only the exceptions are named, and the TUF is the exception.
#
# ── Usage ───────────────────────────────────────────────────────────────
# Sourced (the normal case -- see idle-action.sh):
#   . ~/.config/hypr/scripts/host-profile.sh
#   host_profile_load        # sets HOST_PROFILE_ID + every knob
#
# Run directly, to inspect or to test another machine's policy from here:
#   ./host-profile.sh                      # report
#   ./host-profile.sh --get IDLE_ENABLED   # one value, for scripts
#   HOST_PROFILE=default ./host-profile.sh # pretend to be the laptop
#
# HOST_PROFILE overrides the DMI lookup; HOST_PROFILE_DIR overrides where
# the .env files are read from. Both exist so the laptop's policy can be
# exercised on the desktop, where it can otherwise never run.

# ---------------------------------------------------------------------------
# DMI product_name → profile id
# ---------------------------------------------------------------------------
# product_name rather than the hostname: the hostname is one `hostnamectl`
# away from changing and is identical ("fedora.home") on a fresh install
# of either machine, whereas DMI is burned into the board and survives a
# reinstall, a rename and a disk swap.
host_profile_id() {
    if [ -n "${HOST_PROFILE:-}" ]; then
        printf '%s\n' "$HOST_PROFILE"
        return 0
    fi

    local product
    product="$(cat /sys/class/dmi/id/product_name 2>/dev/null)" || product=""

    case "$product" in
        # "ASUS TUF Gaming A15 FA507NV_FA507NV" here; the glob keeps the
        # match working across the A15's other board revisions.
        "ASUS TUF Gaming A15"*) printf 'asus-tuf-a15\n' ;;
        *)                      printf 'default\n' ;;
    esac
}

# Directory holding the profiles. Resolved relative to this file rather
# than hardcoded to ~/.config, so the repo checkout works as-is too.
_host_profile_dir() {
    if [ -n "${HOST_PROFILE_DIR:-}" ]; then
        printf '%s\n' "$HOST_PROFILE_DIR"
    else
        printf '%s\n' "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/hosts"
    fi
}

# ---------------------------------------------------------------------------
# host_profile_load — populate the knobs for this machine
# ---------------------------------------------------------------------------
# default.env first, then the machine's own file on top. Missing files are
# not an error: the built-in fallbacks below are the same policy default.env
# states, so a half-installed checkout degrades to "behave like a laptop"
# rather than to "behave unpredictably".
host_profile_load() {
    local dir id

    dir="$(_host_profile_dir)"
    id="$(host_profile_id)"
    HOST_PROFILE_ID="$id"
    HOST_PROFILE_FILES=""

    # Built-in fallbacks, overridden by whatever the files below set.
    IDLE_ENABLED="${IDLE_ENABLED:-1}"
    IDLE_ALLOW="${IDLE_ALLOW:-dim undim lock dpms-off dpms-on suspend}"
    IDLE_REQUIRE_BATTERY="${IDLE_REQUIRE_BATTERY:-1}"

    if [ -r "$dir/default.env" ]; then
        # shellcheck source=/dev/null
        . "$dir/default.env"
        HOST_PROFILE_FILES="$dir/default.env"
    fi

    if [ "$id" != "default" ]; then
        if [ -r "$dir/$id.env" ]; then
            # shellcheck source=/dev/null
            . "$dir/$id.env"
            HOST_PROFILE_FILES="$HOST_PROFILE_FILES $dir/$id.env"
        else
            # Only reachable via an explicit HOST_PROFILE typo: the DMI
            # lookup never returns an id it has no file for.
            echo "host-profile: no profile '$id' in $dir, using default only" >&2
        fi
    fi
}

# ---------------------------------------------------------------------------
# CLI (only when executed, not when sourced)
# ---------------------------------------------------------------------------
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    set -u
    export LC_ALL=C
    host_profile_load

    case "${1:-}" in
        --get)
            var="${2:-}"
            [ -n "$var" ] || { echo "usage: $0 --get <VAR>" >&2; exit 2; }
            printf '%s\n' "${!var-}"
            ;;
        ""|--report)
            echo "profile : $HOST_PROFILE_ID"
            echo "product : $(cat /sys/class/dmi/id/product_name 2>/dev/null || echo unknown)"
            echo "files   :${HOST_PROFILE_FILES:- (none found)}"
            echo
            echo "IDLE_ENABLED         = $IDLE_ENABLED"
            echo "IDLE_ALLOW           = $IDLE_ALLOW"
            echo "IDLE_REQUIRE_BATTERY = $IDLE_REQUIRE_BATTERY"
            ;;
        *)
            echo "usage: $0 [--report|--get <VAR>]" >&2
            exit 2
            ;;
    esac
fi
