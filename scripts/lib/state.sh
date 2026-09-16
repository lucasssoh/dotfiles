#!/usr/bin/env bash
# state.sh — the persistent memory the install path never had.
#
# Until this file existed, nothing in the install path remembered anything
# between runs: no fingerprint, no version, no timestamp, no record of what
# a previous run did. STATE_DIR was already defined in status.sh but held
# only log files. Every notion of "has this changed?" was therefore ad hoc
# (`command -v X`, `[ -d ... ]`, `fc-list | grep`), and whatever had no such
# check simply re-ran -- which is why three full LTO Rust builds happened on
# every single `./install user`.
#
# Format: one `key<TAB>value` per line, sorted, in $STATE_DIR/state.v1.
#
# Deliberately NOT JSON: this file has to be readable on a freshly installed
# machine where jq is not in yet (jq arrives with the Hyprland module, very
# late). scripts/hardware-detect.sh already hand-rolls its JSON output for
# exactly this reason -- see its emit_json comment.
#
# Deliberately NOT a shell fragment to `source`: it is DATA, written from
# values that ultimately come from filenames and command output. Sourcing it
# would make any of those an arbitrary-code-execution vector, and would turn
# a corrupted file into a syntax error in the middle of an install instead of
# a value that fails a comparison.
#
# Bumping STATE_SCHEMA is the deliberate reset lever: every machine then does
# one full re-apply, which is the honest behaviour when the meaning of the
# stored values changes. Same idea as FILTER_VERSION in
# config/hyprland/scripts/wallpaper-cache-watcher.sh, which already documents
# why a content check cannot see a change in the ALGORITHM that consumes it.

[ -n "${_STATE_SH_LOADED:-}" ] && return 0
_STATE_SH_LOADED=1

: "${STATE_DIR:=${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles}"
STATE_FILE="$STATE_DIR/state.v1"
STATE_SCHEMA=1

declare -A ST=()
_STATE_LOADED=0

# state_load — reads STATE_FILE into ST. Safe to call when the file does not
# exist yet (first run): ST stays empty and every lookup returns its default,
# so every module reads as "never applied".
state_load() {
    ST=()
    _STATE_LOADED=1
    mkdir -p "$STATE_DIR"
    [ -f "$STATE_FILE" ] || return 0

    local k v
    while IFS=$'\t' read -r k v; do
        [ -n "$k" ] && ST["$k"]="$v"
    done < "$STATE_FILE"

    # An unrecognised schema is treated as no state at all rather than as an
    # error: the safe fallback is to re-apply everything, never to act on
    # values whose meaning we no longer know.
    if [ "${ST[schema]:-0}" != "$STATE_SCHEMA" ]; then
        ST=()
        ST[schema]="$STATE_SCHEMA"
    fi
    return 0
}

# state_get <key> [default]
state_get() { printf '%s' "${ST[$1]:-${2-}}"; }

# state_set <key> <value>
# Tabs and newlines are stripped, not escaped: they are the format's only two
# metacharacters, no legitimate value here contains one (fingerprints,
# timestamps, exit codes, `cargo --version`), and stripping keeps the reader
# a plain `while IFS=$'\t' read`.
state_set() {
    _STATE_LOADED=1
    local v="$2"
    v="${v//$'\t'/ }"
    v="${v//$'\n'/ }"
    ST["$1"]="$v"
}

state_unset() { unset 'ST[$1]'; }

# state_save — atomic rewrite. Callers save eagerly (right after each module
# or crate finishes) rather than once at the end, so a run interrupted with
# Ctrl-C keeps everything it actually accomplished.
state_save() {
    # Without this guard a caller that forgot state_load would silently
    # truncate real state to whatever few keys it happened to set.
    if [ "$_STATE_LOADED" != 1 ]; then
        echo "state_save: refusing to write — state_load was never called" >&2
        return 1
    fi
    mkdir -p "$STATE_DIR"
    ST[schema]="$STATE_SCHEMA"

    local tmp="$STATE_FILE.tmp.$$"
    local k
    for k in "${!ST[@]}"; do
        printf '%s\t%s\n' "$k" "${ST[$k]}"
    done | LC_ALL=C sort > "$tmp" || { rm -f "$tmp"; return 1; }
    mv -f "$tmp" "$STATE_FILE"
}
