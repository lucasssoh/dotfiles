#!/usr/bin/env bash
# =========================================================
# wallpaper-cache-watcher.sh — keeps the "filtered" image cache up to date:
# every wallpaper fitted to every connected screen's resolution, one folder
# per resolution (~/.cache/filtered_wallpapers/<W>x<H>/), read by
# hypr/scripts/wallpaper-set. Launched by Hyprland's autostart
# (hyprland.lua), runs continuously; a pass also runs when a screen is
# plugged in.
#
#   wallpaper-cache-watcher.sh --once   one pass, then exit (the install hook:
#                                       no session yet, so wallpaper-filter
#                                       reads the screens from the kernel)
#
# Also owns keeping WALL_DIR itself in sync: it's a generated symlink farm
# merging the dotfiles repo's wallpapers/ (the GNOME default designs) with
# whatever extra folders are listed in prisme/wallpapers-extra.conf (e.g. a
# private repo holding the bulk of the collection -- see that file for the
# format; same merge set_wallpapers.sh builds for the initial/manual
# setup). Watching the SOURCE folders instead of WALL_DIR itself means
# dropping a new image straight into any of them is enough -- no need to
# rerun set_wallpapers.sh by hand.
#
# The per-image processing itself (wallpaper-filter, ~/.local/bin/) is
# native -- a Rust binary built from prisme-src/src/bin/wallpaper-
# filter.rs (same crate as Prisme, see install.sh), not a bash script
# calling ImageMagick multiple times per image. This script only handles
# orchestration: source-dir watching, the merged-dir sync, the initial
# parallel pass, the cache version marker.
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
THUMB_CACHE_DIR="$HOME/.cache/wallpaper_thumbs"
FILTER_BIN="$HOME/.local/bin/wallpaper-filter"

# The repo's own wallpapers/ -- resolved from this script's real path
# (it's symlinked into ~/.config/hypr/scripts by install.sh and invoked
# from there, so `readlink -f` is needed before walking up to the repo
# root; see set_wallpapers.sh for the sibling logic this mirrors).
ONCE=0
[[ "${1:-}" == "--once" ]] && ONCE=1
SELF="$(readlink -f "${BASH_SOURCE[0]}")"
REPO_ROOT="$(cd "$(dirname "$SELF")/../../.." && pwd)"
DOTFILES_SRC="$REPO_ROOT/wallpapers"

# Extra source folders merged in on top of DOTFILES_SRC -- see
# prisme/wallpapers-extra.conf for the format. Read once at startup (like
# WALLPAPERS_CONF above): editing it needs a restart of this script to
# take effect.
EXTRA_SOURCES_CONF="$HOME/.config/prisme/wallpapers-extra.conf"
EXTRA_SOURCES=()
if [[ -f "$EXTRA_SOURCES_CONF" ]]; then
    while IFS= read -r line; do
        EXTRA_SOURCES+=("${line/#\~\//$HOME/}")
    done < <(grep -vE '^[[:space:]]*(#|$)' "$EXTRA_SOURCES_CONF")
fi

mkdir -p "$CACHE_DIR"

# Rebuilds WALL_DIR as a symlink farm merging DOTFILES_SRC and every
# configured EXTRA_SOURCES entry (same principle as set_wallpapers.sh's
# one-shot setup, run here on every relevant change instead of only on
# manual request). Stale symlinks (source file renamed/deleted, or a
# folder removed from wallpapers-extra.conf) are pruned; existing ones are
# left as-is (ln -sfn is a no-op if already correct).
sync_merged_dir() {
    mkdir -p "$WALL_DIR"
    touch "$WALL_DIR/.wallpapers-merged"
    for src in "$DOTFILES_SRC" "${EXTRA_SOURCES[@]}"; do
        [[ -d "$src" ]] || continue
        for f in "$src"/*; do
            [[ -f "$f" ]] || continue
            ln -sfn "$f" "$WALL_DIR/$(basename "$f")"
        done
    done
    find "$WALL_DIR" -maxdepth 1 -xtype l -delete
}

sync_merged_dir

# wallpaper-filter's freshness check only compares source/cache mtimes: it
# can't see a change in the filter ALGORITHM, only a change in the source
# image. Without this marker, already-cached files would keep the old
# filter version's render indefinitely. Bump this on every pipeline change
# in prisme-src/src/bin/wallpaper-filter.rs (screen-fit cache AND
# thumbnail cache -- same binary, same version, purged together) --
# targeted purge (not an `rm -rf` of the whole folder) to never touch the
# marker itself or step outside these two cache dirs.
# 9: one folder per screen resolution instead of one flat folder.
FILTER_VERSION=9
VERSION_FILE="$CACHE_DIR/.filter-version"
if [[ "$(cat "$VERSION_FILE" 2>/dev/null)" != "$FILTER_VERSION" ]]; then
    find "$CACHE_DIR" -maxdepth 2 -type f \
        \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o -iname "*.webp" -o -iname "*.jxl" \) \
        -delete
    find "$CACHE_DIR" -mindepth 1 -maxdepth 1 -type d -empty -delete
    find "$THUMB_CACHE_DIR" -maxdepth 1 -type f -iname "*.thumb.jpg" -delete
    printf '%s\n' "$FILTER_VERSION" > "$VERSION_FILE"
fi

# One pass: every image, one at a time -- NOT in parallel. Each call holds a
# full-resolution source decode plus the derived buffers in RAM; with ~80+
# wallpapers including 8K photos, launching them all at once (the previous
# `&` + a single trailing `wait`) saturated RAM and froze the machine.
# wallpaper-filter decodes each image once and derives every screen size
# from that decode, so several screens cost one decode per image, not one
# per image and screen. Its freshness check makes an unchanged image a
# no-op, so a pass is cheap when nothing changed. A lock keeps two passes
# (a screen plugged in during an inotify pass) from running at once. One
# notification sums up the pass instead of one per image.
run_pass() {
    (
        flock 9
        local fitted=0 line sizes=()
        while IFS= read -r -d '' img; do
            while IFS= read -r line; do
                if [[ "$line" == fitted\ * ]]; then
                    fitted=$((fitted + 1))
                    sizes+=("${line##* }")
                fi
            done < <("$FILTER_BIN" "$img")
        done < <(find -L "$WALL_DIR" -maxdepth 1 -type f \
            \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o -iname "*.webp" -o -iname "*.jxl" \) \
            -print0)
        if (( fitted > 0 )); then
            local res
            res="$(printf '%s\n' "${sizes[@]}" | sort -u | paste -sd ' ')"
            echo "[wallpapers] $fitted fitted ($res)"
            [[ -n "${WAYLAND_DISPLAY:-}" ]] && notify-send "Wallpapers ready" "$fitted fitted for $res" --expire-time 3000 2>/dev/null
        fi
    ) 9>"$CACHE_DIR/.lock"
}

run_pass
[[ "$ONCE" == 1 ]] && exit 0

# A screen plugged in (or a new mode) needs its own size: listen to
# Hyprland's event socket and run a pass on every monitor added.
if [[ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]] && command -v socat >/dev/null; then
    (
        socat -U - "UNIX-CONNECT:${XDG_RUNTIME_DIR}/hypr/${HYPRLAND_INSTANCE_SIGNATURE}/.socket2.sock" |
            while IFS= read -r event; do
                [[ "$event" == monitoradded* ]] && run_pass
            done
    ) &
fi

# Continuous watching: watches the two SOURCE folders (not WALL_DIR --
# nothing should be dropped there directly, it's fully generated) for
# additions, removals or renames. On any event: resync the merged
# symlink farm, then rescan it exactly like the initial pass above --
# wallpaper-filter's own freshness check (cache_is_fresh) makes that a
# cheap no-op for every image that didn't actually change, so there's no
# need to figure out which specific file the event was about.
watch_dirs=()
[[ -d "$DOTFILES_SRC" ]] && watch_dirs+=("$DOTFILES_SRC")
for src in "${EXTRA_SOURCES[@]}"; do
    [[ -d "$src" ]] && watch_dirs+=("$src")
done

if [[ ${#watch_dirs[@]} -gt 0 ]]; then
    inotifywait -m -e close_write,moved_to,delete,moved_from --format '%e' "${watch_dirs[@]}" | \
        while read -r _event; do
            sync_merged_dir
            run_pass
        done
fi
