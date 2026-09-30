#!/usr/bin/env bash
# Classic snap support: /snap -> /var/lib/snapd/snap.
. "$(dirname "$(readlink -f "$0")")/../../../lib/hook.sh"

if [ -e /snap ] || [ -L /snap ]; then
    info "/snap already present"
else
    as_root ln -s /var/lib/snapd/snap /snap
    ok "/snap linked"
fi
