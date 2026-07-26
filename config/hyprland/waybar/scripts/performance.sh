#!/bin/bash
# =========================================================
# performance.sh — module waybar affichant le profil d'alimentation
# actif (performance/équilibré/économie), via power-profiles-daemon.
#
#   performance.sh          -> JSON pour le module waybar (défaut, inchangé)
#   performance.sh roue-gen -> régénère ~/.config/roue/wheels/powerprofile.toml
#                               avec `active = true` sur le profil en cours,
#                               juste avant que la roue ne s'ouvre (cf.
#                               hypr/keybinds.lua, SUPER+SHIFT+Delete) --
#                               même principe que display-layout.sh roue-gen.
# =========================================================

cmd_status() {
    local profile icon label
    profile=$(powerprofilesctl get)
    case "$profile" in
        performance) icon="";  label="Performance" ;;
        balanced)    icon="󰾅"; label="Balanced" ;;
        power-saver) icon="󰌪"; label="Power Saver" ;;
        *)           icon="󰈐"; label="Unknown" ;;
    esac
    echo "{\"text\": \"$icon\", \"tooltip\": \"Power profile: $label\\nClick: change\"}"
}

# L'état (quel profil est actif) vient de power-profiles-daemon, pas d'un
# fichier figé du dépôt -- ce TOML n'a donc pas de version statique
# versionnée (contrairement à power.toml), il est réécrit à chaque appui,
# comme wheels/display.toml (cf. scripts/display-layout.sh::cmd_roue_gen).
# `active = true` sur le secteur du profil courant affiche la bande d'état
# sur la roue (cf. roue-src/src/wheel.rs).
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
