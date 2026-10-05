#!/bin/sh
# Super + Space: fuzzel. With Boussole installed, what it launches goes
# through `boussole gate` first, which asks before a game during a study
# session and launches everything else at once. Without it, plain fuzzel.
gate="$HOME/.local/bin/boussole"
if [ -x "$gate" ]; then
    exec fuzzel --launch-prefix="$gate gate --" "$@"
fi
exec fuzzel "$@"
