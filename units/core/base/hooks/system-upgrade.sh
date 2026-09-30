#!/usr/bin/env bash
# Bring a fresh machine up to date, once.
. "$(dirname "$(readlink -f "$0")")/../../../lib/hook.sh"

once system-upgrade || { info "already done on this machine"; exit 0; }
as_root dnf upgrade -y --refresh
done_once system-upgrade
ok "system up to date"
