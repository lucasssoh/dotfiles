#!/usr/bin/env bash
# Restart the audio stack so new PipeWire/WirePlumber config is read.
. "$(dirname "$(readlink -f "$0")")/../../../lib/hook.sh"

if systemctl --user is-active --quiet pipewire; then
    systemctl --user restart pipewire pipewire-pulse wireplumber
    ok "audio stack restarted"
else
    info "pipewire not running: the config is read at next login"
fi
