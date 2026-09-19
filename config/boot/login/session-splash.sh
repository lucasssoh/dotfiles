#!/bin/sh
# coucou-session-splash -- hold the word on screen while Hyprland starts.
#
# There is a black gap between the greeter exiting and the compositor's
# first frame: a second or so where the machine looks switched off again,
# which is the whole complaint this module started from, arriving late.
#
# Nothing fancy is needed to close it. A VT keeps showing whatever was
# last drawn on it until something takes the display away -- and what
# takes it away is Hyprland's first modeset. So writing the word to the
# console immediately before exec'ing the session leaves it on screen for
# exactly the duration of the gap, and it disappears because the desktop
# replaced it, not because anything timed out.
#
# No second Plymouth, deliberately. Re-showing the real splash would mean
# a daemon holding DRM master while the compositor is trying to take it,
# and the animated version of this would cost a fight over the device to
# save a second. This is text in the console font -- JetBrains Mono, the
# same face and the same word on the same black -- so the continuity is
# real even though the mechanism is trivial.
#
# Never fails: a decoration must not be able to stop a login.

set -u

WORD="coucou"
TTY="${COUCOU_SPLASH_TTY:-/dev/tty1}"

if [ -w "$TTY" ]; then
    # The console's own idea of its size, so this follows the font cell
    # rather than assuming one. Falls back to the 8x16 geometry on a
    # 1920x1200 panel if stty cannot answer.
    size="$(stty size < "$TTY" 2>/dev/null)" || size=""
    rows="${size% *}"
    cols="${size#* }"
    case "${rows}x${cols}" in
        *[!0-9x]* | x* | *x) rows=75; cols=240 ;;
    esac

    # coucou.script's LOGO_CENTRE, so the console word lands where the
    # splash's word just was. Change one and change the other.
    row=$(( rows * 50 / 100 ))
    col=$(( (cols - ${#WORD}) / 2 + 1 ))
    [ "$row" -lt 1 ] && row=1
    [ "$col" -lt 1 ] && col=1

    # Hide the cursor, clear the screen and its scrollback, place the word.
    printf '\033[?25l\033[2J\033[3J\033[%d;%dH%s' "$row" "$col" "$WORD" > "$TTY" 2>/dev/null || true
fi

# greetd hands the session VT1 as its stdout with nothing in between, and
# Hyprland writes ~15 lines before it reads its config and goes quiet.
# Those would land on the screen in the very gap this splash is covering.
# systemd-cat execvp()s, so it replaces itself and start-hyprland stays
# greetd's direct child -- watchdog, signals and session tracking intact.
# Read them back with `journalctl -t hyprland -b`.
exec systemd-cat -t hyprland /usr/bin/start-hyprland
