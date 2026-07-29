#!/bin/bash
# =========================================================
# performance.sh — waybar module showing the active power profile
# (performance/balanced/power-saver), via power-profiles-daemon.
#
#   performance.sh          -> JSON for the waybar module (default, unchanged)
#   performance.sh roue-gen -> regenerates ~/.config/roue/wheels/powerprofile.toml
#                               with `active = true` on the current profile,
#                               right before the wheel opens (see
#                               hypr/keybinds.lua, SUPER+SHIFT+Delete) --
#                               same principle as display-layout.sh roue-gen.
# =========================================================

cmd_status() {
    local profile icon label
    profile=$(powerprofilesctl get)
    # Icons chosen to read at a glance, distinct from the metrics group's
    # gauge/leaf glyphs: flame (intensity), balance scale (matches the
    # roue wheel's scale.svg for this same profile), battery-with-plus
    # (headroom saved, clearer than the previous ambiguous leaf).
    case "$profile" in
        performance) icon="󰈸"; label="Performance" ;;
        balanced)    icon="󰗑"; label="Balanced" ;;
        power-saver) icon="󰂏"; label="Power Saver" ;;
        *)           icon="󰈐"; label="Unknown" ;;
    esac
    # "class" (= profile name) drives the highlight color in style.css
    # (#custom-performance.performance/.balanced/.power-saver) -- same
    # pattern as custom/display and custom/notification below.
    echo "{\"text\": \"$icon\", \"class\": \"$profile\", \"tooltip\": \"Power profile: $label\\nClick: change\"}"
}

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
action = "powerprofilesctl set performance && pkill -RTMIN+1 waybar"
accent = "yellow"
$active_performance

[[segment]]
icon = "scale.svg"
label = "Balanced"
action = "powerprofilesctl set balanced && pkill -RTMIN+1 waybar"
$active_balanced

[[segment]]
icon = "leaf.svg"
label = "Power saver"
action = "powerprofilesctl set power-saver && pkill -RTMIN+1 waybar"
accent = "green"
$active_power_saver
EOF
}

case "${1:-status}" in
    status)   cmd_status ;;
    roue-gen) cmd_roue_gen ;;
    *)        echo "usage: $0 {status|roue-gen}" >&2; exit 1 ;;
esac
