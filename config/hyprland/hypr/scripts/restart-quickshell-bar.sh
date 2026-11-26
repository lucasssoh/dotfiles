#!/usr/bin/env bash
set -euo pipefail

# --force restarts even when the position is unchanged: the bar's watcher
# calls it for every settings change, not only a move to another edge.
force=false
[[ "${1:-}" == "--force" ]] && force=true

lock_file="${XDG_RUNTIME_DIR:-/tmp}/quickshell-bar-restart-${UID}.lock"
exec 9>"$lock_file"
if ! flock -w 10 9; then
    printf 'Another QuickShell bar restart is still running\n' >&2
    exit 1
fi

bar_config="$HOME/.config/hypr/bar.json"
[[ -e "$bar_config" ]] || bar_config="$HOME/.config/hypr/bar-position.json"
settings="$(python3 - "$bar_config" <<'PY'
import json
import sys

radius = 36
gap = 7
try:
    with open(sys.argv[1], encoding="utf-8") as f:
        config = json.load(f)
except FileNotFoundError:
    config = {}
except (OSError, json.JSONDecodeError) as error:
    print(f"Invalid bar config: {error}; using top/36/7", file=sys.stderr)
    config = {}

value = config.get("position", "top") if isinstance(config, dict) else None
if value not in ("top", "bottom"):
    print("Invalid bar position; using top", file=sys.stderr)
    value = "top"

if isinstance(config, dict):
    # none, narrow, medium or wide; an older number snaps to the nearest.
    radii = {"none": 0, "narrow": 16, "medium": 26, "wide": 36}
    candidate = config.get("radius", "wide")
    if isinstance(candidate, str) and candidate in radii:
        radius = radii[candidate]
    elif isinstance(candidate, (int, float)) and not isinstance(candidate, bool):
        radius = min(radii.values(), key=lambda r: abs(r - candidate))
    else:
        print("Invalid bar radius; using wide", file=sys.stderr)
    candidate = config.get("gap", 7)
    if isinstance(candidate, (int, float)) and not isinstance(candidate, bool):
        gap = max(0, min(24, round(candidate)))
    elif candidate is not None:
        print("Invalid bar gap; using 7", file=sys.stderr)

print(value)
print(radius)
print(gap)
PY
)"
position="$(sed -n 1p <<<"$settings")"
radius="$(sed -n 2p <<<"$settings")"
gap="$(sed -n 3p <<<"$settings")"
export QUICKSHELL_BAR_POSITION="$position"

# The window rounding and the gap round the windows are the same knobs as
# the bar's curves. Keep a copy of each for hyprland.lua's next load and
# apply them now, so saving bar.json is enough even when the bar itself
# does not need restarting.
for pair in "bar-radius:$radius" "bar-gap:$gap"; do
    file="$HOME/.config/hypr/${pair%%:*}"
    printf '%s\n' "${pair#*:}" > "$file.tmp"
    mv -f "$file.tmp" "$file"
done
if command -v hyprctl >/dev/null 2>&1; then
    # This Hyprland uses the Lua config API: `hyprctl keyword` answers
    # "unknown request", while `hl.config` applies at runtime.
    hyprctl eval "hl.config({ decoration = { rounding = $radius }, general = { gaps_out = { top = $gap, right = $gap, bottom = $gap, left = $gap } } })" >/dev/null 2>&1 || true
fi

mapfile -t pids < <(quickshell list --all | awk '
    /^Instance / { pid = "" }
    /^[[:space:]]+Process ID:/ { pid = $3 }
    /^[[:space:]]+Config path: .*\/quickshell\/bar\/shell\.qml$/ {
        print pid
    }
')

bar_position() {
    local pid=$1
    [[ -r "/proc/$pid/environ" ]] || return 1
    tr '\0' '\n' < "/proc/$pid/environ" | sed -n 's/^QUICKSHELL_BAR_POSITION=//p'
}

wait_for_bar() {
    for ((attempt = 0; attempt < 200; attempt++)); do
        if [[ "$(hyprctl layers 2>/dev/null)" == *"namespace: quickshell-bar-$position"* ]]; then
            sleep 0.1
            return 0
        fi
        sleep 0.05
    done
    return 1
}

old_bar_layer_present() {
    local layers pid
    layers="$(hyprctl layers 2>/dev/null)" || return 2
    for pid in "${pids[@]}"; do
        if grep -Eq "namespace: quickshell-bar-(top|bottom), pid: ${pid}([[:space:]]|$)" <<<"$layers"; then
            return 0
        fi
    done
    return 1
}

wait_for_old_bar_layer_to_unmap() {
    local status
    for ((attempt = 0; attempt < 10; attempt++)); do
        if old_bar_layer_present; then
            sleep 0.025
        else
            status=$?
            if (( status == 1 )); then
                return 0
            fi
            printf 'Could not query Hyprland layers before restart\n' >&2
            return 1
        fi
    done
    return 1
}

if ! $force && (( ${#pids[@]} == 1 )) && [[ "$(bar_position "${pids[0]}")" == "$position" ]]; then
    exit 0
fi

if (( ${#pids[@]} > 0 )); then
    for pid in "${pids[@]}"; do
        if [[ ! "$pid" =~ ^[0-9]+$ ]]; then
            printf 'Invalid QuickShell PID: %s\n' "$pid" >&2
            exit 1
        fi
    done

    if ! wait_for_old_bar_layer_to_unmap; then
        printf 'QuickShell bar layer did not unmap within 250 ms; stopping the old process anyway\n' >&2
    fi

    for pid in "${pids[@]}"; do
        kill -TERM "$pid"
    done

    for ((attempt = 0; attempt < 30; attempt++)); do
        alive=0
        for pid in "${pids[@]}"; do
            if kill -0 "$pid" 2>/dev/null; then
                alive=1
                break
            fi
        done
        if (( alive == 0 )); then
            break
        fi
        sleep 0.1
    done

    for pid in "${pids[@]}"; do
        if kill -0 "$pid" 2>/dev/null; then
            printf 'QuickShell bar did not stop (PID %s)\n' "$pid" >&2
            exit 1
        fi
    done
fi

if ! "$HOME/.config/hypr/scripts/bar-tint.py"; then
    printf 'Could not refresh the bar tint profile; continuing with the previous profile\n' >&2
fi

quickshell --daemonize --config bar 9>&-

if ! wait_for_bar; then
    printf 'QuickShell bar did not map in time\n' >&2
    exit 1
fi
