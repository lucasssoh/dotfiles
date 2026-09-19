#!/usr/bin/env bash
# preview.sh -- watch the splash now, instead of rebooting to find out.
#
# Plymouth draws through DRM on a VT, and Fedora builds no X11 renderer,
# so there is no window to preview in: the closest thing is the real
# daemon on a real console. This script deploys the theme (without
# touching the initramfs), starts plymouthd on a spare VT, switches to
# it, and switches back.
#
# IT DOES NOT WORK ON EVERY MACHINE, and this one is one of the awkward
# ones. Plymouth renders to whatever DRM device it can open. At boot that
# is simpledrm on /dev/dri/card0, which exists from the moment the kernel
# registers the EFI framebuffer; once i915 takes over the panel it becomes
# card1 and simpledrm is released, so on a booted system card0 is GONE.
# A hand-started plymouthd then finds no device it will open, cannot start
# a graphical splash, and silently falls back to the text one -- which
# looks exactly like a theme that draws nothing.
#
# So the check below reads the daemon log for that specific failure and
# says so, rather than letting a black screen be blamed on the theme. When
# it fires, the real diagnosis is a real boot:
#
#     sudo grubby --update-kernel=ALL --args="plymouth.debug"
#     (reboot, then read /var/log/plymouth-debug.log)
#     sudo grubby --update-kernel=ALL --remove-args="plymouth.debug"
#
#   ./preview.sh              12 seconds of the boot splash
#   ./preview.sh 25           longer
#   ./preview.sh --sweep      drive the bar 0→100% over the duration
#   ./preview.sh --status     the same, plus a fake boot log under the bar
#   ./preview.sh --password   exercise the passphrase prompt
#   ./preview.sh --shutdown   the shutdown splash instead of the boot one
#
# Switching VTs takes the screen away from Hyprland for the duration, so
# everything that puts it back -- quitting the daemon, returning to the
# original console -- runs from a trap AND from a detached watchdog. The
# watchdog is the one that matters: a trap cannot fire if this script is
# killed outright, and being left staring at a dead VT with no way back
# is a much worse failure than a preview that ends early.

set -Eeuo pipefail

BOLD="\e[1m"; GREEN="\e[32m"; YELLOW="\e[33m"; BLUE="\e[34m"; RESET="\e[0m"
info() { echo -e "${BLUE}[INFO]${RESET}  $*"; }
ok()   { echo -e "${GREEN}[ OK ]${RESET}  $*"; }
warn() { echo -e "${YELLOW}[WARN]${RESET}  $*"; }

REPO_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"

DURATION=12
VT="${PLYMOUTH_PREVIEW_VT:-6}"
MODE=boot
DEMO=none

while [ $# -gt 0 ]; do
    case "$1" in
        --sweep)    DEMO=sweep ;;
        --status)   DEMO=status ;;
        --password) DEMO=password ;;
        --shutdown) MODE=shutdown ;;
        --vt)       VT="$2"; shift ;;
        [0-9]*)     DURATION="$1" ;;
        *)          echo "unknown argument: $1" >&2; exit 2 ;;
    esac
    shift
done

# One password prompt up front, so nothing below stalls half-way through
# with the screen already handed over to another console.
sudo -v

FROM_VT="$(sed 's/^tty//' /sys/class/tty/tty0/active)"
case "$FROM_VT" in ''|*[!0-9]*) FROM_VT=1 ;; esac
[ "$FROM_VT" = "$VT" ] && { echo "already on tty$VT; pick another with --vt" >&2; exit 2; }

info "deploying the theme (no initramfs rebuild)"
DEPLOY_LOG="$(mktemp)"
if ! "$REPO_DIR/install.sh" --no-initramfs >"$DEPLOY_LOG" 2>&1; then
    cat "$DEPLOY_LOG" >&2
    rm -f "$DEPLOY_LOG"
    exit 1
fi
rm -f "$DEPLOY_LOG"

# A leftover daemon owns the console and would ignore everything below.
sudo plymouth --ping 2>/dev/null && sudo plymouth quit 2>/dev/null || true

WATCHDOG_PID_FILE="$(mktemp)"
cleanup() {
    if [ -s "$WATCHDOG_PID_FILE" ]; then
        sudo kill "$(cat "$WATCHDOG_PID_FILE")" 2>/dev/null || true
    fi
    rm -f "$WATCHDOG_PID_FILE"
    sudo plymouth quit 2>/dev/null || true
    sudo chvt "$FROM_VT" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

# The safety net: detached, outlives this shell, puts the screen back even
# if the shell is killed. It reports its own pid through a file -- `setsid
# --fork` returns as soon as it has forked, so the pid of the command that
# started it is not the pid of the process to cancel.
sudo setsid --fork bash -c \
    "echo \$\$ > '$WATCHDOG_PID_FILE'; sleep $((DURATION + 20)); plymouth quit 2>/dev/null; chvt $FROM_VT"
for _ in 1 2 3 4 5 6 7 8 9 10; do
    [ -s "$WATCHDOG_PID_FILE" ] && break
    sleep 0.1
done

LOG=/tmp/plymouth-preview.log
sudo rm -f "$LOG"
sudo plymouthd --mode="$MODE" --tty="/dev/tty$VT" --no-boot-log \
               --debug --debug-file="$LOG"

# plymouthd daemonises, so its exit status says nothing about whether it
# is alive. A previous run of this script left no log at all and gave no
# clue why; refusing to continue without a daemon is what makes the next
# failure legible.
if ! sudo plymouth --ping 2>/dev/null; then
    echo "plymouthd did not come up." >&2
    [ -s "$LOG" ] && { echo "--- $LOG ---" >&2; sudo tail -40 "$LOG" >&2; } \
                  || echo "(no $LOG was written either)" >&2
    exit 1
fi

sudo plymouth show-splash

info "switching to tty$VT for ${DURATION}s (back to tty$FROM_VT afterwards)"
sudo chvt "$VT"

case "$DEMO" in
    sweep|status)
        # Drives on_system_update() rather than the boot-progress estimate:
        # a known 0→100 ramp is the only way to judge the bar's easing.
        if [ "$DEMO" = status ]; then
            # The fake boot log is defined once, in simulate.py, and
            # replayed here through the real daemon -- which is the only
            # way to find out whether Image.Text() actually draws on this
            # machine, and at what size.
            python3 "$REPO_DIR/simulate.py" --print-schedule \
                    --boot-duration "$DURATION" \
            | while IFS=$'\t' read -r delay unit; do
                  sleep "$delay"
                  sudo plymouth update --status="$unit" 2>/dev/null || true
              done &
            STATUS_FEED=$!
        fi
        STEPS=$((DURATION * 4))
        for i in $(seq 0 "$STEPS"); do
            sudo plymouth system-update --progress=$(( i * 100 / STEPS )) 2>/dev/null || true
            sleep 0.25
        done
        if [ -n "${STATUS_FEED:-}" ]; then
            kill "$STATUS_FEED" 2>/dev/null || true
        fi
        ;;
    password)
        sleep $(( DURATION / 3 ))
        # --command consumes the answer and throws it away; this is a
        # drawing test, not an authentication one.
        printf '' | sudo timeout $(( DURATION * 2 / 3 )) \
            plymouth ask-for-password --prompt="Passphrase" --command=/bin/cat \
            >/dev/null 2>&1 || true
        sleep $(( DURATION / 3 ))
        ;;
    *)
        sleep "$DURATION"
        ;;
esac

cleanup
trap - EXIT INT TERM
ok "back on tty$FROM_VT. Daemon log: $LOG"
# Distinguish "this machine cannot preview" from "this theme is broken".
# Both end as a blank screen; only one of them is worth debugging.
if sudo grep -q 'could not find suitable rendering plugin' "$LOG" 2>/dev/null; then
    warn "plymouthd found no DRM device it could open, so it fell back to the"
    warn "text splash. NOTHING here says anything about the theme."
    warn
    warn "Expected on this hardware after boot: the splash renders on simpledrm"
    warn "(/dev/dri/card0), and that device is released once i915 claims the"
    warn "panel as card1. Present now:"
    ls /dev/dri/ 2>/dev/null | sed 's/^/    /'
    warn
    warn "To see what the theme really does, debug a real boot instead:"
    warn "  sudo grubby --update-kernel=ALL --args=\"plymouth.debug\""
    warn "  reboot, then read /var/log/plymouth-debug.log"
    warn "  sudo grubby --update-kernel=ALL --remove-args=\"plymouth.debug\""
elif sudo grep -iE 'error|failed|could not|not found' "$LOG" 2>/dev/null | head -20; then
    warn "^ the daemon reported the above."
else
    info "no errors in the daemon log."
fi
