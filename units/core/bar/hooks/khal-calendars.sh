#!/usr/bin/env bash
# khal fails on a calendar whose folder is missing. Its config declares
# personal, plus Boussole's etude and cours: make sure all three exist.
. "$(dirname "$(readlink -f "$0")")/../../../lib/hook.sh"

for cal in personal etude cours; do
    mkdir -p "$HOME/.local/share/khal/calendars/$cal"
done
ok "khal calendars ready"
