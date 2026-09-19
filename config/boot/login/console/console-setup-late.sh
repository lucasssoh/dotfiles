#!/usr/bin/env bash
# console-setup-late -- put the keymap back, whatever else happens.
#
# Read /etc/vconsole.conf and apply it, in the order that matters: the
# keymap first, the font second, neither able to fail the unit.
#
# The ordering is the whole point. systemd-vconsole-setup does font first
# and treats a font failure as fatal to the keymap, which is how a French
# keyboard ends up in US QWERTY at a password prompt. Here the keymap goes
# in before anything that can fail is attempted, and a font that will not
# load costs a typeface rather than a login.

set -u

# shellcheck disable=SC1091
[ -r /etc/vconsole.conf ] && . /etc/vconsole.conf

if [ -n "${KEYMAP:-}" ]; then
    loadkeys "$KEYMAP" >/dev/null 2>&1 \
        || echo "console-setup-late: loadkeys '$KEYMAP' failed" >&2
fi

if [ -n "${FONT:-}" ]; then
    setfont "$FONT" >/dev/null 2>&1 \
        || echo "console-setup-late: setfont '$FONT' failed" >&2
fi

# Loading a font does not re-translate what is already on screen. The
# console stores GLYPH INDICES per cell, not characters, so anything
# painted under the previous font keeps its indices and is redrawn with
# the new one -- which is how a greeter ended up with a background of "@"
# where its spaces had been. The font's Latin-1 identity layout now makes
# that harmless, but clearing costs nothing and removes the class of
# problem rather than the instance. Safe here because this runs before
# greetd: there is nothing yet on VT1 worth keeping.
if [ -w /dev/tty1 ]; then
    printf '\033[H\033[2J\033[3J' > /dev/tty1 2>/dev/null || true
fi

# Never fail the unit: this is a repair step, and a repair step that marks
# the boot degraded teaches people to ignore a degraded boot.
exit 0
