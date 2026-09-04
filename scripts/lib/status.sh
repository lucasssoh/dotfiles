#!/usr/bin/env bash
# scripts/lib/status.sh — compact terminal status + persistent log, for the
# top-level installer orchestrators only (install_all.sh, setup_fedora.sh).
#
# NOT sourced by individual config/*/install.sh: those stay fully autonomous
# and verbose when run directly on their own. This lib only changes how the
# orchestrators present *their* output -- each module keeps running as a
# real subprocess with its own set -e / info-ok-warn, untouched.
#
# Vocabulary: ✓ done, ⠋ running (static glyph; on a TTY an indented, dimmed
# line right below it live-updates with the module's own current output
# line -- see run_step), ○ skipped / not applicable, ✗ failed.

: "${BOLD:=\e[1m}"
: "${GREEN:=\e[32m}"
: "${YELLOW:=\e[33m}"
: "${RED:=\e[31m}"
: "${BLUE:=\e[34m}"
: "${RESET:=\e[0m}"

STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles"
STATUS_NAMES=()
STATUS_RESULTS=()

# status_init — creates the state dir and a fresh timestamped log file for
# this run, with a "latest.log" symlink pointing at it.
status_init() {
    mkdir -p "$STATE_DIR"
    LOG_FILE="$STATE_DIR/install-$(date +%Y%m%d-%H%M%S).log"
    : > "$LOG_FILE"
    ln -sfn "$(basename "$LOG_FILE")" "$STATE_DIR/latest.log"
    echo -e "${BLUE}[INFO]${RESET}  Detailed log: $LOG_FILE"
}

_is_tty() { [ -t 1 ]; }

# Single-line redraw of whatever the cursor is currently sitting on --
# used by skip_step (always one line, nothing runs) and as run_step's own
# non-TTY fallback.
_line_done() {
    local glyph="$1" color="$2" label="$3"
    if _is_tty; then echo -e "\r\033[K${color}${glyph}${RESET} ${label}"
    else              echo "${glyph} ${label}"
    fi
}

# ---- run_step's two-line TTY layout -----------------------------------
# Line A: "⠋ label", printed once, stays put while the step runs.
# Line B, directly under it: the module's own current output line,
# indented and dimmed -- redrawn in place as new lines arrive, never
# stacking up. On completion, line A is rewritten with the final glyph and
# line B is cleared, leaving one settled line per step -- same footprint
# as before, just no longer dark while it runs.

# Reserves the two-line block for one step: prints "⠋ label" then a
# newline, so the cursor lands on the (still empty) sub-status line B.
_step_begin() {
    local label="$1"
    if _is_tty; then printf '⠋ %s\n' "$label"
    else              echo "… ${label}"
    fi
}

# Redraws line B in place with the module's latest output line, indented
# one level further and dimmed so it clearly reads as detail, not as its
# own status line.
_step_detail() {
    local text="$1" cols="$2"
    local avail=$(( cols - 4 ))
    [ "$avail" -lt 1 ] && avail=1
    [ "${#text}" -gt "$avail" ] && text="${text:0:$((avail - 1))}…"
    printf '\r\033[K    \033[2m%s\033[0m' "$text"
}

# Moves back up to line A, replaces "⠋ label" with the final glyph, then
# clears line B -- leaving the cursor there, ready for the next step's
# _step_begin to land on the very line just cleared.
_step_finish() {
    local glyph="$1" color="$2" label="$3"
    printf '\033[1A\r\033[K%b%s%b %s\n\033[K' "$color" "$glyph" "$RESET" "$label"
}

# run_step <label> <command...>
#
# Runs <command...> as a real subprocess (never sourced). Its full
# stdout+stderr always lands in LOG_FILE; on a TTY, each line ALSO
# live-updates an indented, dimmed line under the spinner (like
# `apt`/`docker pull`'s scrolling "currently doing this" line) instead of
# going dark until the step finishes. Prints a compact one-line ✓/✗ status
# once done. Returns the command's real exit code.
#
# Callers under `set -e` should invoke this as `run_step ... || true` (see
# install_all.sh): that does NOT hide the failure -- the exit code is
# already recorded in STATUS_RESULTS and in the log before this returns; the
# `|| true` only keeps `errexit` from killing the caller's loop early, which
# is the point (continue the remaining steps, fail the run at the end).
run_step() {
    local label="$1"; shift
    _step_begin "$label"

    printf '===== [%s] %s -- START =====\n' "$(date '+%F %T')" "$label" >> "$LOG_FILE"
    local start rc
    start=$(date +%s)

    if _is_tty; then
        local cols
        cols=$(tput cols 2>/dev/null || echo 80)
        # A real pipeline (not `< <(...)`): PIPESTATUS[0] below is "$@"'s
        # own exit code, not the while-loop's -- needed since the loop is
        # what's on the right of the pipe.
        "$@" 2>&1 | while IFS= read -r line; do
            printf '%s\n' "$line" >> "$LOG_FILE"
            _step_detail "$line" "$cols"
        done
        rc=${PIPESTATUS[0]}
    else
        "$@" >> "$LOG_FILE" 2>&1
        rc=$?
    fi

    printf '===== [%s] %s -- END (exit=%d, %ds) =====\n' \
        "$(date '+%F %T')" "$label" "$rc" "$(( $(date +%s) - start ))" >> "$LOG_FILE"

    STATUS_NAMES+=("$label")
    if [ "$rc" -eq 0 ]; then
        STATUS_RESULTS+=("ok")
        if _is_tty; then _step_finish "✓" "$GREEN" "$label"; else _line_done "✓" "$GREEN" "$label"; fi
    else
        STATUS_RESULTS+=("fail")
        if _is_tty; then _step_finish "✗" "$RED" "$label"; else _line_done "✗" "$RED" "$label"; fi
    fi
    return "$rc"
}

# skip_step <label> [reason]
#
# Marks a step ○ without running anything. Vocabulary kept available for a
# future hardware-conditional module; not forced onto anything today.
skip_step() {
    local label="$1" reason="${2:-not applicable}"
    printf '===== [%s] %s -- SKIPPED (%s) =====\n' "$(date '+%F %T')" "$label" "$reason" >> "$LOG_FILE"
    STATUS_NAMES+=("$label")
    STATUS_RESULTS+=("skip")
    _line_done "○" "$YELLOW" "$label"
}

# status_summary — prints the final ✓/✗/○ recap and the log path.
# Returns 1 if at least one step failed, 0 otherwise.
status_summary() {
    echo -e "\n${BOLD}── Summary ──${RESET}\n"
    local failed=()
    local i
    for i in "${!STATUS_NAMES[@]}"; do
        case "${STATUS_RESULTS[$i]}" in
            ok)   echo -e "  ${GREEN}✓${RESET} ${STATUS_NAMES[$i]}" ;;
            fail) echo -e "  ${RED}✗${RESET} ${STATUS_NAMES[$i]}"; failed+=("${STATUS_NAMES[$i]}") ;;
            skip) echo -e "  ${YELLOW}○${RESET} ${STATUS_NAMES[$i]}" ;;
        esac
    done
    echo
    echo -e "${BLUE}[INFO]${RESET}  Full log: $LOG_FILE"
    if [ "${#failed[@]}" -gt 0 ]; then
        echo -e "${YELLOW}[WARN]${RESET}  Failed: ${failed[*]} — see $LOG_FILE"
        return 1
    fi
    echo -e "${GREEN}[ OK ]${RESET}  All steps succeeded."
    return 0
}

# redirect_output_to_log — for linear scripts with no sub-modules
# (setup_fedora.sh): sends everything from this call on to LOG_FILE, and
# redefines info/ok/warn to keep writing to the real terminal (saved as fd
# 3) so existing narration stays visible. Call after status_init and after
# info/ok/warn are first defined by the caller.
redirect_output_to_log() {
    exec 3>&1 4>&2
    exec >> "$LOG_FILE" 2>&1
    info() { echo -e "${BLUE}[INFO]${RESET}  $*" >&3; }
    ok()   { echo -e "${GREEN}[ OK ]${RESET}  $*" >&3; }
    warn() { echo -e "${YELLOW}[WARN]${RESET}  $*" >&3; }
}
