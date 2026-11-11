#!/usr/bin/env bash
set -euo pipefail

lock_file="${XDG_RUNTIME_DIR:-/tmp}/quickshell-bar-restart-${UID}.lock"
exec 9>"$lock_file"
if ! flock -w 10 9; then
    printf 'Another QuickShell bar restart is still running\n' >&2
    exit 1
fi

position="$(python3 - "$HOME/.config/hypr/bar-position.json" <<'PY'
import json
import sys

try:
    with open(sys.argv[1], encoding="utf-8") as f:
        config = json.load(f)
except FileNotFoundError:
    print("top")
except (OSError, json.JSONDecodeError) as error:
    print(f"Invalid bar position config: {error}; using top", file=sys.stderr)
    print("top")
else:
    value = config.get("position") if isinstance(config, dict) else None
    if value not in ("top", "bottom"):
        print("Invalid bar position; using top", file=sys.stderr)
        value = "top"
    print(value)
PY
)"
export QUICKSHELL_BAR_POSITION="$position"

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

if (( ${#pids[@]} == 1 )) && [[ "$(bar_position "${pids[0]}")" == "$position" ]]; then
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
