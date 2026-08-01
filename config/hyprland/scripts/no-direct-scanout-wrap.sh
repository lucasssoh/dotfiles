#!/usr/bin/env bash
# Steam/Lutris launch wrapper: disables render:direct_scanout for the
# lifetime of the wrapped command, then restores the config's default (auto).
#
# Why: some HDR fullscreen games (confirmed: Resident Evil Village / RE
# Engine via winewayland + PROTON_ENABLE_HDR) go full black in real
# fullscreen because their HDR10 swapchain hits the same NVIDIA
# wp_color_manager_v1 gap documented for KCD2/Cyberpunk, but on the direct
# scanout path it blacks the DRM plane instead of just muting HDR. Forcing
# Hyprland to composite (direct_scanout=0) instead of scanning the raw
# buffer straight to the plane works around it. Scoped to just this game's
# process lifetime so other fullscreen games (e.g. KCD2, which is fine with
# direct_scanout=2) keep the scanout perf/latency benefit.
#
# Usage (Steam launch options): ~/.config/hypr/scripts/no-direct-scanout-wrap.sh %command%
set -uo pipefail

hyprctl eval "hl.config({ render = { direct_scanout = 0 } })" >/dev/null

"$@"
status=$?

hyprctl eval "hl.config({ render = { direct_scanout = 2 } })" >/dev/null
exit "$status"
