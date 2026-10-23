#!/usr/bin/env bash
# Boussole's planner became Programme: its settings and journal move over,
# nothing lost, and Boussole's service, link and binary go. The name
# `boussole` then belongs to Boussole, the course app.
#
#   ~/.config/boussole/settings.json       → ~/.config/programme/
#   ~/.local/share/boussole/<planner's>    → ~/.local/share/programme/
#
# Only the planner's own files move: Boussole's config.yaml, state.db and
# guide/ stay where they are. What Programme no longer reads (the course
# files' outlines, focus mode, the session tracker) goes to
# ~/.local/share/programme/from-boussole/, with a copy of every file as it
# was. Run again, it finds nothing left to move.
. "$(dirname "$(readlink -f "$0")")/../../../lib/hook.sh"

old_cfg="$HOME/.config/boussole"
old_data="$HOME/.local/share/boussole"
cfg="$HOME/.config/programme"
data="$HOME/.local/share/programme"
keep="$data/from-boussole"

# The planner's service first: nothing writes while its files move.
if systemctl --user cat boussole.service >/dev/null 2>&1; then
    systemctl --user disable --now boussole.service >/dev/null 2>&1 || true
    ok "boussole.service stopped and disabled"
fi
unit_link="$HOME/.config/systemd/user/boussole.service"
if [ -L "$unit_link" ] && readlink "$unit_link" | grep "systemd/boussole.service" >/dev/null; then
    rm -f "$unit_link"
    systemctl --user daemon-reload || true
fi

moved=0
mkdir -p "$cfg" "$data" "$keep"
if [ -f "$old_cfg/settings.json" ]; then
    cp -p "$old_cfg/settings.json" "$keep/settings.json"
    if [ -f "$cfg/settings.json" ]; then
        warn "$cfg/settings.json exists already: Boussole's planner's kept in $keep"
    else
        mv "$old_cfg/settings.json" "$cfg/settings.json"
        moved=1
    fi
fi

# The journal is the source of truth: never over one Programme wrote.
if [ -f "$old_data/journal.jsonl" ]; then
    cp -p "$old_data/journal.jsonl" "$keep/journal.jsonl"
    if [ -s "$data/journal.jsonl" ]; then
        warn "$data/journal.jsonl exists already: Boussole's planner's kept in $keep"
    else
        mv "$old_data/journal.jsonl" "$data/journal.jsonl"
        moved=1
    fi
fi
# Caches and the last timetable, rebuilt anyway if missing.
for f in state.json plan.json ade.json alerts.json; do
    [ -f "$old_data/$f" ] || continue
    if [ -s "$data/journal.jsonl" ] && ! cmp -s "$data/journal.jsonl" "$keep/journal.jsonl"; then
        mv "$old_data/$f" "$keep/$f"
    else
        mv -f "$old_data/$f" "$data/$f"
    fi
    moved=1
done
for f in outlines.json focus.json seance.json; do
    [ -f "$old_data/$f" ] || continue
    mv "$old_data/$f" "$keep/$f"
    moved=1
done
rmdir "$old_cfg" "$old_data" 2>/dev/null || true
rmdir "$keep" 2>/dev/null || true

# The planner's binary in ~/.local/bin: a link to its RPM, or a local
# build that says "boussole 1.x". Anything else there (Boussole's own
# launcher) is left alone.
bin="$HOME/.local/bin/boussole"
if [ -L "$bin" ] && [ "$(readlink "$bin")" = "/usr/bin/boussole" ]; then
    rm -f "$bin"
    ok "the planner's ~/.local/bin/boussole link removed"
elif [ -f "$bin" ] && [ ! -L "$bin" ] && head -c 4 "$bin" | grep -a "ELF" >/dev/null \
     && "$bin" --version 2>/dev/null | grep -E "^boussole 1\." >/dev/null; then
    rm -f "$bin" "$HOME/.local/bin/boussole.before-room"
    ok "the planner's local build ~/.local/bin/boussole removed"
fi

# The planner's sessions in khal's etude calendar: Programme writes its own.
rm -f "$HOME/.local/share/khal/calendars/etude"/boussole-*.ics 2>/dev/null || true

if [ "$moved" = 1 ]; then
    systemctl --user try-restart programme.service || true
    ok "Boussole's planner's settings and journal now Programme's"
else
    ok "nothing of Boussole's planner left to move"
fi
