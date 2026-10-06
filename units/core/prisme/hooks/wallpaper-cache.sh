#!/usr/bin/env bash
# Fit every wallpaper to the screens found at install time, so the first
# session starts with the cache ready (the watcher keeps it up to date after).
. "$(dirname "$(readlink -f "$0")")/../../../lib/hook.sh"

bash "$REPO/config/hyprland/scripts/wallpaper-cache-watcher.sh" --once
ok "wallpaper cache ready"

# A new machine starts on coucou-shell's own wallpaper, the Relief pair:
# light or dark with the colour scheme. A playlist that already exists is
# the user's choice and is never replaced.
playlist="$HOME/.config/hypr/wallpaper-playlist.json"
default="coucou-aube-relief.jxl"
if [ ! -e "$playlist" ]; then
    wall_dir="$HOME/Images/Wallpapers"
    conf="$HOME/.config/prisme/wallpapers.conf"
    if [ -f "$conf" ]; then
        configured="$(grep -vE '^[[:space:]]*(#|$)' "$conf" | head -n1)"
        [ -n "$configured" ] && wall_dir="${configured/#\~\//$HOME/}"
    fi
    mkdir -p "$(dirname "$playlist")"
    printf '{"mode":"static","source":"%s","walls":["%s"],"last_static":"%s"}\n' \
        "$wall_dir" "$default" "$default" > "$playlist"
    ok "default wallpaper: $default"
fi
