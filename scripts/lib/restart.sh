#!/usr/bin/env bash
# restart.sh — "what is still running the old version?"
#
# This tool follows the package-manager model, which was an explicit choice:
# dnf, apt and pacman put files on disk and restart NOTHING. A running process
# keeps the code it already mapped; the new version takes effect the next time
# it starts. They tell you what is stale (Fedora's `needs-restarting`, Debian's
# needrestart) and leave the decision to you -- because restarting a process is
# a judgement only you can make. Cutting the audio stack mid-call to apply a
# config change is not a service.
#
# So nothing here restarts anything. It reports.
#
# Detection, in order of strength:
#
#   1. /proc/<pid>/exe ending in " (deleted)". This is the strongest possible
#      signal and it costs one readlink: `install -Dm755` replaces the file's
#      INODE, so a process started before the replacement holds an open handle
#      to a file with no name left. It cannot be a false positive.
#   2. Binary mtime newer than the process start time, for the case where the
#      binary was modified in place rather than replaced.
#
# Both are facts read off /proc, not guesses about what a module "probably"
# touched.
#
# quickshell is deliberately absent from the report: it watches its own QML and
# reloads itself, so it is never stale in the sense that matters here. Saying
# otherwise would train you to ignore the report.

[ -n "${_RESTART_SH_LOADED:-}" ] && return 0
_RESTART_SH_LOADED=1

# needs_restart_scan -> one "<pid>\t<binary>\t<reason>" line per stale process.
# Empty output means nothing is stale. Always exits 0.
needs_restart_scan() {
    local p pid exe bin bmtime pstart
    for p in /proc/[0-9]*; do
        pid="${p#/proc/}"
        exe="$(readlink "$p/exe" 2>/dev/null)" || continue

        case "$exe" in
            "$HOME/.local/bin/"*) ;;
            *) continue ;;
        esac

        if [ "${exe% (deleted)}" != "$exe" ]; then
            bin="${exe% (deleted)}"
            printf '%s\t%s\t%s\n' "$pid" "$bin" "binaire remplace depuis le demarrage"
            continue
        fi

        [ -f "$exe" ] || continue
        bmtime="$(stat -c %Y "$exe" 2>/dev/null)" || continue
        pstart="$(stat -c %Y "$p" 2>/dev/null)" || continue
        if [ "$bmtime" -gt "$pstart" ]; then
            printf '%s\t%s\t%s\n' "$pid" "$exe" "binaire plus recent que le processus"
        fi
    done
    return 0
}

# _unit_for_pid <pid> -> the user unit owning it, or empty.
# Turns "pid 2547 is stale" into an actionable command instead of a number.
_unit_for_pid() {
    local u
    u="$(systemctl --user list-units --type=service --state=running --no-legend --plain 2>/dev/null \
         | awk '{print $1}' \
         | while read -r unit; do
               [ "$(systemctl --user show -p MainPID --value "$unit" 2>/dev/null)" = "$1" ] \
                   && { printf '%s' "$unit"; break; }
           done)"
    printf '%s' "$u"
}

# needs_restart_report — human output. Returns 0 when nothing is stale, 1 when
# something is, so a caller can decide whether to mention it at all.
needs_restart_report() {
    local rows; rows="$(needs_restart_scan)"
    [ -z "$rows" ] && return 0

    echo
    echo "Ces elements tournent encore sur une version anterieure :"
    local pid bin reason unit name
    while IFS=$'\t' read -r pid bin reason; do
        [ -n "$pid" ] || continue
        name="$(basename "$bin")"
        unit="$(_unit_for_pid "$pid")"
        if [ -n "$unit" ]; then
            printf '  %-20s %s\n' "$name" "$reason"
            printf '  %-20s → systemctl --user restart %s\n' "" "$unit"
        else
            printf '  %-20s %s (pid %s)\n' "$name" "$reason" "$pid"
            printf '  %-20s → a relancer quand ca t arrange\n' ""
        fi
    done <<< "$rows"
    echo
    echo "Rien n a ete redemarre : les fichiers sont en place, la nouvelle version"
    echo "prendra effet au prochain demarrage de chacun."
    return 1
}
