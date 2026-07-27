#!/usr/bin/env bash
# =========================================================
# wallpaper-cache-watcher.sh — keeps the "filtered" image cache up to date
# (cropped/extended to the active screen's format, never cropping the axis
# that would carry the main subject), applied automatically by Prisme
# (prisme-src/src/apply.rs) when available, and by the old
# set_wallpaper.sh's "Filtered" mode. Launched by Hyprland's autostart
# (hyprland.lua), runs continuously.
#
# The per-image processing itself (wallpaper-filter, ~/.local/bin/) is
# native -- a Rust binary built from prisme-src/src/bin/wallpaper-
# filter.rs (same crate as Prisme, see install.sh), not a bash script
# calling ImageMagick multiple times per image. This script only handles
# orchestration: inotify watching, the initial parallel pass, the cache
# version marker.
# =========================================================
# Source folder configurable via ~/.config/prisme/wallpapers.conf (one
# line, absolute path or prefixed with ~/) -- same file read by Prisme
# (prisme-src/src/wallpapers.rs) and the other scripts in this pipeline,
# so there's only one folder to change. Falls back to the default if the
# file is absent, empty, or contains only comments.
WALL_DIR="$HOME/Images/Wallpapers"
WALLPAPERS_CONF="$HOME/.config/prisme/wallpapers.conf"
if [[ -f "$WALLPAPERS_CONF" ]]; then
    configured="$(grep -vE '^[[:space:]]*(#|$)' "$WALLPAPERS_CONF" | head -n1)"
    [[ -n "$configured" ]] && WALL_DIR="${configured/#\~\//$HOME/}"
fi
CACHE_DIR="$HOME/.cache/filtered_wallpapers"
FILTER_BIN="$HOME/.local/bin/wallpaper-filter"

mkdir -p "$CACHE_DIR"

# wallpaper-filter's freshness check only compares source/cache mtimes: it
# can't see a change in the filter ALGORITHM, only a change in the source
# image. Without this marker, already-cached files would keep the old
# filter version's render indefinitely. Bump this on every pipeline change
# in prisme-src/src/bin/wallpaper-filter.rs -- targeted purge (not an
# `rm -rf` of the whole folder) to never touch the marker itself or step
# outside CACHE_DIR. Done here, before the parallel loop below, and nowhere
# else: wallpaper-filter is launched in parallel (~30 instances via `&` +
# `wait`), a test-and-purge per instance would create a race (one instance
# would purge what another just wrote).
FILTER_VERSION=4
VERSION_FILE="$CACHE_DIR/.filter-version"
if [[ "$(cat "$VERSION_FILE" 2>/dev/null)" != "$FILTER_VERSION" ]]; then
    find "$CACHE_DIR" -maxdepth 1 -type f \
        \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o -iname "*.webp" \) \
        -delete
    printf '%s\n' "$FILTER_VERSION" > "$VERSION_FILE"
fi

# Initial pass: generates the cache for all images already present
while IFS= read -r -d '' img; do
    "$FILTER_BIN" "$img" &
done < <(find -L "$WALL_DIR" -maxdepth 1 -type f \
    \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o -iname "*.webp" \) \
    -print0)

wait

# Continuous watching: regenerates the cache as soon as an image is added
# or modified in the wallpapers folder
inotifywait -m -e close_write,moved_to --format '%w%f' "$(readlink -f "$WALL_DIR")" | \
    while read -r filepath; do
        "$FILTER_BIN" "$filepath" &
    done
