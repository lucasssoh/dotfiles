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

# Which keys THIS process has written or removed. state_save applies only
# these to the file and leaves every other line alone -- see its comment for
# why that distinction is the whole point.
declare -A _ST_DIRTY=()

# Whether this process has read the file. Only state_load and state_save set
# it; state_set deliberately does not, because having written a key is not
# the same as having read the others, and rust_build keys off this to decide
# whether it still has to load.
_STATE_LOADED=0

# state_load — reads STATE_FILE into ST. Safe to call when the file does not
# exist yet (first run): ST stays empty and every lookup returns its default,
# so every module reads as "never applied".
state_load() {
    ST=()
    _ST_DIRTY=()
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
    local v="$2"
    v="${v//$'\t'/ }"
    v="${v//$'\n'/ }"
    ST["$1"]="$v"
    _ST_DIRTY["$1"]='set'
}

# A removal has to be remembered as a removal: state_save reads the file back
# before writing, so a key merely dropped from ST would come straight back.
state_unset() { unset 'ST[$1]'; _ST_DIRTY["$1"]='unset'; }

# state_save — merge this process's changes into the file, atomically.
#
# ── Why a merge and not a rewrite ───────────────────────────────────────
# The writers are not one process. Every module runs as its own script (see
# run_step in bin/cc-pkg-mng), with its own copy of ST, and rust_build
# writes the crate.* keys from inside that child while the parent still
# holds an ST that predates them. A save that wrote ST wholesale therefore
# had the parent erase, at its very next save, every key the child had just
# written: on the first machine to install this, the three crate.* keys were
# recorded during the Hyprland module at 15:13, 15:15 and 15:16, and were
# gone again at 15:16:58 when the module's own bookkeeping was saved. The
# binaries were current; `verify` reported all three crates as never built,
# and no amount of rebuilding could clear it.
#
# So a save claims only the keys THIS process actually touched (_ST_DIRTY),
# and reads everything else back off the file untouched. The order in which
# parent and child save stops mattering, which is the property the previous
# version lacked -- and which is why the old guard below is gone rather than
# repaired. It refused to write for a caller that had not called state_load,
# to stop exactly this truncation; it never fired, because state_set marked
# the state as loaded, and a caller that writes one key is now harmless
# anyway.
#
# No lock: parent and child never write at once (run_step waits for the
# module to exit before saving). The read-modify-write below would still
# lose an update against a genuinely concurrent writer, which nothing here
# is.
#
# Callers save eagerly (right after each module or crate finishes) rather
# than once at the end, so a run interrupted with Ctrl-C keeps everything it
# actually accomplished.
state_save() {
    mkdir -p "$STATE_DIR"

    # The file as it stands, including anything written since this process
    # loaded. An unrecognised schema is dropped rather than merged -- the
    # same rule state_load applies, for the same reason: never carry forward
    # values whose meaning we no longer know.
    declare -A merged=()
    local k v
    if [ -f "$STATE_FILE" ]; then
        while IFS=$'\t' read -r k v; do
            [ -n "$k" ] && merged["$k"]="$v"
        done < "$STATE_FILE"
        [ "${merged[schema]:-0}" = "$STATE_SCHEMA" ] || merged=()
    fi

    # Our own changes on top, removals included: a tombstone has to be
    # applied here, or state_unset would be undone by the read above.
    for k in "${!_ST_DIRTY[@]}"; do
        if [ "${_ST_DIRTY[$k]}" = 'unset' ]; then
            unset 'merged[$k]'
        else
            merged["$k"]="${ST[$k]}"
        fi
    done
    merged[schema]="$STATE_SCHEMA"

    local tmp="$STATE_FILE.tmp.$$"
    for k in "${!merged[@]}"; do
        printf '%s\t%s\n' "$k" "${merged[$k]}"
    done | LC_ALL=C sort > "$tmp" || { rm -f "$tmp"; return 1; }
    mv -f "$tmp" "$STATE_FILE"

    # Memory now matches the file -- which tells this process more than it
    # knew a moment ago: a parent that never saw the child's crate.* keys
    # picks them up here. The dirty set is cleared because those values have
    # landed.
    ST=()
    for k in "${!merged[@]}"; do ST["$k"]="${merged[$k]}"; done
    _ST_DIRTY=()
    _STATE_LOADED=1
}
