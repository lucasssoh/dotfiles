#!/usr/bin/env bash
# Load the hardware monitoring modules the bar reads temperatures from.
. "$(dirname "$(readlink -f "$0")")/../../../lib/hook.sh"

as_root sensors-detect --auto >/dev/null
ok "sensors detected"
