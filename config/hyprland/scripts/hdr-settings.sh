#!/usr/bin/env bash
# hdr-settings.sh — shared HDR/SDR tuning + per-screen persistence.
#
# Sourced by BOTH waybar/scripts/hdr.sh (the manual per-screen toggle) and
# scripts/workspace-manager.sh (which re-asserts every active monitor's
# mode/position/scale on hyprland.start, config.reloaded, monitor.added and
# monitor.removed). Without this file, workspace-manager used to hardcode
# every external back to SDR on each of those events, silently undoing
# whatever the user had just picked via the waybar toggle (e.g. reconnecting
# a cable, or any Hyprland config reload while a game had HDR on) — annoying
# enough on its own, and actively harmful when a game's own in-game HDR
# stayed on while the desktop side got reset to SDR underneath it (see the
# mismatched-HDR/SDR note in the HDR memory). This file is what lets
# workspace-manager reapply the user's LAST CHOICE instead of a fixed
# default.
#
# State is keyed by the monitor's `description` (make+model+serial, from
# `hyprctl monitors -j`), NOT its connector name — names aren't stable
# across replugs/reboots (e.g. DP-2 becoming DP-9), but description is tied
# to the physical panel.

HDR_STATE_FILE="$HOME/.config/hypr/hdr-state.json"

# ---- Tuning (moved here from hdr.sh so workspace-manager can reapply the
#      exact same values, not an approximation) ------------------------
SDRBRIGHTNESS="1.0"     # SDR content brightness while the screen is in HDR (1.0..2.0)
SDRSATURATION="1.0"     # SDR content saturation in HDR
SDR_WHITE_LUMINANCE="203"  # SDR white level inside the HDR container (ITU-R BT.2408 diffuse
                            # white, matches Hyprland's own fixed HDR_REF_LUMINANCE; default: 80)

# HDR headroom sent to clients (monitorv2 min_luminance / max_luminance /
# max_avg_luminance -- see src/config/lua/bindings/LuaBindingsConfigRules.cpp
# in Hyprland's source). Empty = fall back to the EDID-reported value (this
# panel: min 0.041, max 1037, max_avg 872 cd/m^2). Hyprland's own HDR white
# reference is hardcoded at 203 cd/m^2 (HDR_REF_LUMINANCE), so these are the
# direct equivalent of the three numbers Windows' "HDR Calibration" app
# measures (min black level / max full-screen / max small-highlight) --
# raising MAX_LUMINANCE above the EDID's reported peak increases the
# perceived punch of highlights (more headroom above the 203 nit reference),
# at the cost of the panel itself clipping anything past its real peak.
MAX_LUMINANCE=""        # cd/m^2, empty = EDID (this panel: 1037)
MAX_AVG_LUMINANCE=""    # cd/m^2, empty = EDID (this panel: 872)

# Builds the bitdepth/cm/... fields to splice into an `hl.monitor({...})`
# call for $1 = "hdr" | "sdr". Deliberately excludes mode/position/scale/
# output -- callers already know those for their own reasons (hdr.sh
# preserves the current ones, workspace-manager sets the grid target).
hdr_extra_clause() {
    if [[ "$1" == "hdr" ]]; then
        # Both floors forced to literal 0 rather than the EDID-reported 0.041
        # cd/m^2: min_luminance is the floor for native HDR content (games,
        # HDR video), sdr_min_luminance only affects SDR windows composited
        # into the HDR container. The EDID value visibly lifted blacks above
        # what the panel can actually do (confirmed against a bare TTY
        # framebuffer, which has no compositor/CM path to introduce a floor).
        local extra="bitdepth = 10, cm = \"hdredid\", sdrbrightness = ${SDRBRIGHTNESS}, sdrsaturation = ${SDRSATURATION}, sdr_max_luminance = ${SDR_WHITE_LUMINANCE}, sdr_min_luminance = 0, min_luminance = 0"
        [[ -n "$MAX_LUMINANCE" ]]     && extra+=", max_luminance = ${MAX_LUMINANCE}"
        [[ -n "$MAX_AVG_LUMINANCE" ]] && extra+=", max_avg_luminance = ${MAX_AVG_LUMINANCE}"
        echo "$extra"
    else
        echo "bitdepth = 8, cm = \"auto\""
    fi
}

# $1 = monitor description. Echoes "hdr" or "sdr" -- "sdr" both when the
# screen has never had a choice saved yet, and if the state file is
# missing/unreadable (fail closed to the old, safe default rather than
# ever guessing a screen into HDR it wasn't already in).
hdr_last_choice() {
    local desc="$1"
    [[ -z "$desc" || ! -f "$HDR_STATE_FILE" ]] && { echo sdr; return; }
    jq -r --arg d "$desc" '.[$d] // "sdr"' "$HDR_STATE_FILE" 2>/dev/null || echo sdr
}

# $1 = monitor description, $2 = "hdr" | "sdr" -- persists the user's choice
# so the next hyprland.start/config.reloaded/monitor.added/monitor.removed
# (workspace-manager.sh) reapplies it instead of resetting to SDR.
hdr_save_choice() {
    local desc="$1" want="$2" tmp
    [[ -z "$desc" ]] && return 0
    mkdir -p "$(dirname "$HDR_STATE_FILE")"
    [[ -f "$HDR_STATE_FILE" ]] || echo '{}' > "$HDR_STATE_FILE"
    tmp="$(mktemp "${HDR_STATE_FILE}.XXXXXX")"
    jq --arg d "$desc" --arg w "$want" '. + {($d): $w}' "$HDR_STATE_FILE" > "$tmp" \
        && mv "$tmp" "$HDR_STATE_FILE" || rm -f "$tmp"
}
