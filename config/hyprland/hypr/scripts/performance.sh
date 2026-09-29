#!/bin/bash
# =========================================================
# performance.sh roue-gen — regenerates ~/.config/roue/wheels/powerprofile.toml
# with `active = true` on the current profile (power-profiles-daemon), right
# before the power-profile wheel opens (hypr/keybinds.lua, SUPER+SHIFT+Delete,
# and the bar's power-profile button) -- same principle as
# display-layout.sh roue-gen.
# =========================================================

# The state (which profile is active) comes from power-profiles-daemon,
# not a file frozen in the repo -- so this TOML has no versioned static
# copy (unlike power.toml), it gets rewritten on every trigger, like
# wheels/display.toml (see scripts/display-layout.sh::cmd_roue_gen).
# `active = true` on the current profile's sector shows the state band
# on the wheel (see roue-src/src/wheel.rs).
cmd_roue_gen() {
    local profile active_performance="" active_balanced="" active_power_saver=""
    profile=$(powerprofilesctl get)
    case "$profile" in
        performance) active_performance="active = true" ;;
        balanced)    active_balanced="active = true" ;;
        power-saver) active_power_saver="active = true" ;;
    esac

    local dir="$HOME/.config/roue/wheels"
    mkdir -p "$dir"
    cat > "$dir/powerprofile.toml" <<EOF
title = "Power profile"

[[segment]]
icon = "zap.svg"
label = "Performance"
action = "powerprofilesctl set performance"
accent = "yellow"
$active_performance

[[segment]]
icon = "wind.svg"
label = "Balanced"
action = "powerprofilesctl set balanced"
$active_balanced

[[segment]]
icon = "leaf.svg"
label = "Power saver"
action = "powerprofilesctl set power-saver"
accent = "green"
$active_power_saver
EOF
}

case "${1:-}" in
    roue-gen) cmd_roue_gen ;;
    *)        echo "usage: $0 roue-gen" >&2; exit 1 ;;
esac
