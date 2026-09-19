#!/usr/bin/env bash
# status-feed.sh -- the boot log, one line at a time, onto the splash.
#
# Plymouth has a status channel (`plymouth update --status=...`, which
# reaches SetUpdateStatusFunction in coucou.script) and essentially
# nothing feeds it. systemd does not talk to Plymouth at all: on Fedora 44
# the only binary shipping a call to plymouth_send_msg is
# systemd-storagetm, and the three units that do send `update --status`
# are Plymouth's own switch-root and read-write services. So the splash
# can show a line of running commentary, but somebody has to write it.
#
# This is that somebody. It polls systemd's job list and pushes the unit
# of the most recently started running job, deduplicated, until the splash
# goes away.
#
# Polling rather than subscribing, deliberately: the event-driven route is
# a D-Bus match on org.freedesktop.systemd1.Manager, which needs the
# system bus, which is itself one of the services this is supposed to be
# narrating -- and it would need a JSON parser in the early boot path. A
# `systemctl list-jobs` five times a second costs one short-lived process
# per tick for the few seconds the splash is up, and it works from the
# moment PID 1 does.
#
# Never fails: a boot splash decoration must not be able to fail a boot.

set -uo pipefail          # not -e -- a failed poll must not end the feed

POLL="${COUCOU_STATUS_POLL:-0.2}"
MAX_SECONDS="${COUCOU_STATUS_MAX:-120}"

last=""
deadline=$(( SECONDS + MAX_SECONDS ))

while [ "$SECONDS" -lt "$deadline" ]; do
    # The splash is the only reason to be running.
    plymouth --ping >/dev/null 2>&1 || break

    # `list-jobs --plain --no-legend` prints "JOB UNIT TYPE STATE". The
    # unit is matched by shape rather than by column number so a change in
    # systemd's table layout degrades into showing nothing, not into
    # showing the word "start" on the boot screen. Jobs are listed by
    # ascending id, so the last running one is the most recent.
    unit="$(systemctl list-jobs --plain --no-legend 2>/dev/null | awk '
        $NF == "running" {
            for (i = 1; i <= NF; i++)
                if ($i ~ /\.[a-z]+$/) { u = $i; break }
        }
        END { if (u != "") print u }
    ')"

    if [ -n "$unit" ] && [ "$unit" != "$last" ]; then
        plymouth update --status="$unit" 2>/dev/null || true
        last="$unit"
    fi

    sleep "$POLL"
done

exit 0
