#!/usr/bin/env bash
# =========================================================
# restore_wallpaper.sh — reapplies the wallpaper at session startup, from
# the state persisted by Prisme/set_wallpaper.sh in
# wallpaper-playlist.json. Launched by Hyprland's autostart
# (hyprland.lua).
#
# Three mutually-exclusive modes: "static" (one image), "dynamic"
# (slideshow service), "solid" (flat color via `awww clear`, no image
# file -- neither Prisme nor set_wallpaper.sh's rofi picker write this
# one yet, it's set by hand, e.g. { "mode": "solid", "color": "000000" }).
# =========================================================

# Source folder configurable via ~/.config/prisme/wallpapers.conf -- only
# used as a fallback, see below (the playlist's "source" is enough in the
# vast majority of cases).
WALL_DIR="$HOME/Images/Wallpapers"
WALLPAPERS_CONF="$HOME/.config/prisme/wallpapers.conf"
if [[ -f "$WALLPAPERS_CONF" ]]; then
    configured="$(grep -vE '^[[:space:]]*(#|$)' "$WALLPAPERS_CONF" | head -n1)"
    [[ -n "$configured" ]] && WALL_DIR="${configured/#\~\//$HOME/}"
fi
PLAYLIST_FILE="$HOME/.config/hypr/wallpaper-playlist.json"

if ! pidof awww-daemon >/dev/null; then
    awww-daemon &
    sleep 0.5
fi

if [ ! -f "$PLAYLIST_FILE" ]; then
    exit 0
fi

MODE=$(python3 -c "import json; print(json.load(open('$PLAYLIST_FILE'))['mode'])")

if [ "$MODE" = "static" ]; then
    # Static mode: make sure the slideshow service isn't active
    systemctl --user stop wallpaper-slideshow.service 2>/dev/null

    SELECTED_WALL=$(python3 -c "import json; print(json.load(open('$PLAYLIST_FILE'))['walls'][0])")
    # `source` is written by Prisme (Original vs Filtered) -- absent from
    # playlists written by the old rofi picker, hence the fallback to
    # WALL_DIR.
    SRC_DIR=$(python3 -c "import json; d = json.load(open('$PLAYLIST_FILE')); print(d.get('source') or '$WALL_DIR')")
    awww img "$SRC_DIR/$SELECTED_WALL" --transition-type none

elif [ "$MODE" = "dynamic" ]; then
    # Dynamic mode: delegates to the dedicated systemd service (slideshow)
    systemctl --user start wallpaper-slideshow.service

elif [ "$MODE" = "solid" ]; then
    # Solid mode: a flat color fill via awww's own `clear`, not an image --
    # no wallpaper file involved, so nothing to look up in WALL_DIR/source.
    # Mutually exclusive with the slideshow, same as static.
    systemctl --user stop wallpaper-slideshow.service 2>/dev/null

    COLOR=$(python3 -c "import json; print(json.load(open('$PLAYLIST_FILE')).get('color', '000000'))")
    awww clear "$COLOR"
fi
