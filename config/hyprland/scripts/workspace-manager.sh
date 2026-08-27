#!/usr/bin/env bash
set -euo pipefail

# ---- Concurrency lock ---------------------------------------------------
# Toggling a monitor's `disabled` state genuinely fires Hyprland's own
# monitor.added/monitor.removed events (confirmed further down, see the
# Quickshell-refresh comment) -- the SAME events that trigger THIS script
# in the first place (hypr/hyprland.lua). One clean run settles into a
# no-op on any later re-run (nothing left to change -> no further
# transitions -> no further events), which is what makes that safe rather
# than a feedback loop. But two overlapping runs, each reading its own
# snapshot of `hyprctl monitors` and issuing hyprctl eval calls
# interleaved with the other's, can each observe a half-applied state and
# "correct" it into something the other run then has to re-correct --
# every correction is itself a real transition, so it keeps firing more
# events instead of converging. That race, not any single run, is what
# actually froze the session hard enough to need a reboot switching
# external-only -> internal-only live. A blocking flock removes the race
# entirely: every invocation still eventually runs (nothing gets dropped,
# unlike a non-blocking skip-if-busy lock would), but strictly one at a
# time, each against a consistent, fully-settled monitor state.
exec 200>"${XDG_RUNTIME_DIR:-/tmp}/hypr-workspace-manager.lock"
flock 200

# =========================================================
# workspace-manager.sh — single engine: active screens, grid position,
# and max refresh rate, resolved BY ROLE (never by connector name —
# names can change between plugs, e.g. DP-2 becoming DP-9 mid-session).
# Every external screen's HDR/SDR state is reapplied here from whatever the
# user last picked via waybar/scripts/hdr.sh (persisted in hdr-state.json,
# see hdr-settings.sh) — never forced to SDR. HDR itself is still never
# auto-*enabled* the first time a screen is seen (unknown screen -> SDR
# default, same as before); this only stops an already-made choice from
# getting silently undone by a reload/hotplug.
#
#   Internal  = 1st monitor whose name matches eDP*/LVDS*/DSI*
#   external  = 1st remaining monitor, in `hyprctl monitors` order
#   external2, external3, ... = every further one, same order
#
#   Workspaces 1-5  -> the MAIN screen      (or the sole active one, if only one is)
#   Workspaces 6-10 -> the SECONDARY screen (ditto)
#
# Split evenly (5/5, not the old 7/3) -- no reason one screen should get
# more slots than the other by default. This 2-way split only ever
# targets internal/first-external (a 3rd+ screen has no dedicated range
# of its own yet -- it's fully positioned/enabled by the grid below, just
# not a `hl.workspace_rule()` target).
#
# "Main" is not hardcoded to internal: it's whichever screen was last used
# SOLO (mode "internal" or "external"), tracked as `main` in the state
# file below and flipped automatically by display-layout.sh every time a
# single-screen mode is chosen. Asked for: a whole session spent in
# external-only mode already spreads windows across the full 1-10 range
# on that one screen -- reconnecting internal and going back to "both"
# used to always reclaim 1-5 for internal regardless of that, forcing a
# manual re-shuffle of everything just opened in 1-5 over to 6-10. Now
# "both" keeps 1-5 on whichever screen was actually main a moment ago.
#
# Which screens are active is read from a persistent JSON state — same
# pattern as the wallpaper system (set_wallpaper.sh / restore_wallpaper.sh
# + wallpaper-playlist.json):
#
#   ~/.config/hypr/display-layout.json
#   { "mode": "both"|"internal"|"external", "main": "internal"|"external" }
#
# Written by scripts/display-layout.sh (rofi menu / waybar module).
# Absent or invalid -> defaults to both / internal. "both" now means ALL
# connected screens (internal + every external), not just the first two —
# see monitor-grid.py below for how a 3rd+ screen actually gets placed.
#
# WHERE each active screen sits is a separate, hand-edited file (this is
# the part that used to be "position": "external-left"/"external-right" +
# "align": a fixed left/right pairing breaks as soon as the external
# screen and the laptop physically swap sides, which happens often enough
# here to be worth a real fix rather than another enum value):
#
#   ~/.config/hypr/monitor-layout.json
#   { "grid": [["external", "internal"]], "align": "center" }
#
# `grid` is a list of rows, each a list of roles (or null for a gap) --
# one row = side by side (horizontal), one column = stacked (vertical),
# more of both = a real grid for 3+ screens, e.g.
# [["external", "external2"], ["internal", null]]. Column widths / row
# heights are each the max size of the monitors placed in them, so
# mismatched resolutions still line up; `align` ("start"|"center"|"end",
# default "center"; "top"/"bottom"/"left"/"right" accepted as synonyms)
# controls where a smaller monitor sits within its row/column. Swapping
# which physical side a screen is on is then just swapping two roles in
# the grid -- `display-layout.sh swap` does exactly that for
# internal/external. Absent or invalid -> defaults to a single row with
# every external (in order) followed by internal, matching the old
# "external-left" default. The actual pixel math is done by
# scripts/monitor-grid.py (see its own header) rather than in bash.
#
# Idempotent: only replays deterministic `hyprctl eval` calls from the
# current state + the two JSON files — safe to rerun with no side effect.
# Called by the hyprland.start / config.reloaded / monitor.added /
# monitor.removed hooks (hypr/hyprland.lua).
#
# NB: this setup loads its config via a custom Lua binding (hl.*),
# which switches Hyprland to a "non-legacy" parser where `hyprctl
# keyword` is refused ("keyword can't work with non-legacy parsers.
# Use eval."). Everything is therefore driven via
# `hyprctl eval '<lua hl.*>'`, which calls exactly the same functions
# as hypr/monitors.lua.
# =========================================================

STATE_FILE="$HOME/.config/hypr/display-layout.json"
LAYOUT_FILE="$HOME/.config/hypr/monitor-layout.json"
SCALE_FILE="$HOME/.config/hypr/scale.json"
source "$HOME/.config/hypr/scripts/hdr-settings.sh"

# ---- Desired active screens (persistent state, defaults if absent/invalid) ----
layout_mode="both"
layout_main="internal"
if [[ -f "$STATE_FILE" ]]; then
    v="$(jq -r '.mode // empty'     "$STATE_FILE" 2>/dev/null || true)"
    if [[ "$v" =~ ^(both|internal|external)$ ]]; then layout_mode="$v"; fi
    v="$(jq -r '.main // empty'     "$STATE_FILE" 2>/dev/null || true)"
    if [[ "$v" =~ ^(internal|external)$ ]]; then layout_main="$v"; fi
fi

# ---- Desired per-screen scale (persistent state, defaults if absent/invalid) ----
# { "internal": "1", "external": "1.25" } -- written by hand for now, no
# menu/dispatcher wired to this file yet.
int_scale="1"
ext_scale="1"
if [[ -f "$SCALE_FILE" ]]; then
    v="$(jq -r '.internal // empty' "$SCALE_FILE" 2>/dev/null || true)"
    if [[ "$v" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then int_scale="$v"; fi
    v="$(jq -r '.external // empty' "$SCALE_FILE" 2>/dev/null || true)"
    if [[ "$v" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then ext_scale="$v"; fi
fi

# ---- All connected monitors, including disabled ones ----------------
# ("monitors -j" alone EXCLUDES disabled screens — needed to resolve
# roles/modes even when a screen was turned off by a previous mode
# choice.)
mons_json="$(hyprctl monitors all -j)"

# ---- Role resolution ------------------------------------------------------

# Internal panel connector read from DRM rather than via `hyprctl
# monitors`, which loses the panel as soon as it's offline. Reading from
# DRM avoids the fallback below misclassifying the external screen as
# internal in "external only" mode (panel off, so absent from monitor
# data), which would make it impossible to switch back to the internal
# display. Dynamic resolution (follows the real connector, never
# hardcoded). Same helper duplicated in scripts/display-layout.sh
# (read-only, for menu display).
internal_from_drm() {
    local d
    # 1) CONNECTED internal connector = this boot's real panel. Handles the
    #    dual-GPU MUX (the panel can appear as card1-eDP-* or card2-eDP-*
    #    depending on the routing chosen at boot): checking the status is
    #    necessary, since the glob's first connector can be a ghost
    #    connector from a GPU not used this boot.
    for d in /sys/class/drm/card*-eDP-* /sys/class/drm/card*-LVDS-* /sys/class/drm/card*-DSI-*; do
        [[ -e "$d" ]] || continue
        [[ "$(cat "$d/status" 2>/dev/null)" == connected ]] || continue
        basename "$d" | sed -E 's/^card[0-9]+-//'
        return 0
    done
    # 2) Fallback: any internal connector, even disabled — avoids getting
    #    stuck in "external only" mode (panel off, absent from the first
    #    pattern above, but still ours).
    for d in /sys/class/drm/card*-eDP-* /sys/class/drm/card*-LVDS-* /sys/class/drm/card*-DSI-*; do
        [[ -e "$d" ]] || continue
        basename "$d" | sed -E 's/^card[0-9]+-//'
        return 0
    done
}

internal="$(internal_from_drm)"
if [[ -z "$internal" ]]; then
    internal="$(jq -r '[.[] | select(.name | test("^(eDP|LVDS|DSI)"))][0].name // empty' <<<"$mons_json")"
fi
if [[ -z "$internal" ]]; then
    # No laptop panel detected (desktop machine): fall back to the 1st listed monitor
    internal="$(jq -r '.[0].name // empty' <<<"$mons_json")"
fi
[[ -z "$internal" ]] && { echo "workspace-manager: aucun moniteur détecté" >&2; exit 0; }

# Every other connected monitor, in `hyprctl monitors` order -- these are
# roles "external", "external2", "external3", ... (role_map_json below),
# never hardcoded to just one: a 3rd+ screen is fully positioned by the
# grid (monitor-grid.py) even though it has no dedicated workspace range
# (see header comment).
externals=()
while IFS= read -r n; do
    [[ -n "$n" && "$n" != "$internal" ]] && externals+=("$n")
done < <(jq -r '.[].name' <<<"$mons_json")
first_external="${externals[0]:-}"

role_map_json="$(jq -n --arg internal "$internal" '{internal: $internal}')"
for i in "${!externals[@]}"; do
    role="external"
    [[ "$i" -gt 0 ]] && role="external$((i + 1))"
    role_map_json="$(jq --arg r "$role" --arg n "${externals[$i]}" '. + {($r): $n}' <<<"$role_map_json")"
done

# ---- Resolving active screens from the desired mode (+ guards) ---
# "both" now means ALL connected screens, not just internal + the first
# external -- a 3rd+ screen used to be left entirely unmanaged (whatever
# position Hyprland's own "auto" gave it at boot).
declare -A active
active["$internal"]=true
for e in "${externals[@]}"; do active["$e"]=true; done
case "$layout_mode" in
    internal)
        for e in "${externals[@]}"; do active["$e"]=false; done
        ;;
    external)
        active["$internal"]=false
        for e in "${externals[@]}"; do active["$e"]=false; done
        [[ -n "$first_external" ]] && active["$first_external"]=true
        ;;
esac
any_active=false
for n in "$internal" "${externals[@]}"; do
    [[ "${active[$n]}" == true ]] && any_active=true
done
[[ "$any_active" != true ]] && active["$internal"]=true   # never zero active screens: fall back to internal

active_internal="${active[$internal]}"
active_external="${active[$first_external]:-false}"

# ---- Workspace target monitors (1-5 / 6-10) -- computed here (used to
#      live only at the bottom) because the migration step below needs
#      it BEFORE the monitor enable/disable dance runs. Which real
#      screen gets which range now follows `layout_main` (see header
#      comment) instead of hardcoding internal = 1-5.
if [[ "$active_internal" == true && "$active_external" == true ]]; then
    if [[ "$layout_main" == "external" ]]; then
        range15_target="$first_external"; range610_target="$internal"
    else
        range15_target="$internal"; range610_target="$first_external"
    fi
elif [[ "$active_internal" == true ]]; then
    range15_target="$internal"; range610_target="$internal"
else
    range15_target="$first_external"; range610_target="$first_external"
fi

# ---- Remembers who has keyboard focus right now, to hand it back at the
#      very end -- the migration step below can steal it (see its own
#      comment on why moving a workspace also switches to it).
pre_focused_monitor="$(jq -r '.[] | select(.focused==true) | .name' <<<"$mons_json")"
pre_focused_ws="$(jq -r --arg m "$pre_focused_monitor" '.[] | select(.name==$m) | .activeWorkspace.id // empty' <<<"$mons_json")"

# ---- Helper: best available refresh rate at the screen's current
#      native resolution (never hardcoded — depends on the panel) ----
best_refresh() {
    local name="$1" w h
    w=$(jq -r --arg m "$name" '.[] | select(.name==$m) | .width'  <<<"$mons_json")
    h=$(jq -r --arg m "$name" '.[] | select(.name==$m) | .height' <<<"$mons_json")
    jq -r --arg m "$name" --argjson w "$w" --argjson h "$h" '
        .[] | select(.name==$m) | .availableModes[]?
        | select(startswith(($w|tostring) + "x" + ($h|tostring) + "@"))
        | capture("@(?<rr>[0-9.]+)Hz").rr | tonumber
    ' <<<"$mons_json" | sort -rn | head -1
}

# ---- Grid layout (logical coordinates) ---------------------------------
# Scale is fixed at 1 (100%) on every screen -- see the hl.monitor() calls
# below -- so logical coordinates are just the physical pixel sizes,
# no per-role division needed.
#
# Default grid if monitor-layout.json is absent/invalid: one row, every
# external (in order) followed by internal -- matches the old
# "external-left" default. Built here (not as a literal) since the
# number of externals varies.
default_grid_roles=("external")
for i in "${!externals[@]}"; do
    [[ "$i" -gt 0 ]] && default_grid_roles+=("external$((i + 1))")
done
default_grid_roles+=("internal")
default_grid_json="$(printf '%s\n' "${default_grid_roles[@]}" | jq -R . | jq -s '[.]')"

grid_json="$default_grid_json"
align="center"
if [[ -f "$LAYOUT_FILE" ]]; then
    v="$(jq -c '.grid // empty' "$LAYOUT_FILE" 2>/dev/null || true)"
    [[ -n "$v" && "$v" != "null" ]] && grid_json="$v"
    v="$(jq -r '.align // empty' "$LAYOUT_FILE" 2>/dev/null || true)"
    case "$v" in
        start|top|left)   align="start" ;;
        end|bottom|right) align="end" ;;
        center)           align="center" ;;
    esac
fi

dims_json="$(jq '[.[] | {(.name): {w: .width, h: .height}}] | add // {}' <<<"$mons_json")"
active_json="{}"
for n in "$internal" "${externals[@]}"; do
    active_json="$(jq --arg n "$n" --argjson v "${active[$n]}" '. + {($n): $v}' <<<"$active_json")"
done

positions_json="$(jq -n \
    --argjson grid "$grid_json" \
    --arg align "$align" \
    --argjson dims "$dims_json" \
    --argjson active "$active_json" \
    --argjson role_map "$role_map_json" \
    '{grid: $grid, align: $align, dims: $dims, active: $active, role_map: $role_map}' \
    | python3 "$HOME/.config/hypr/scripts/monitor-grid.py")"

# Any active monitor missing from positions_json (not placed in the
# grid -- typo'd role, or a screen just plugged in and not added to
# monitor-layout.json yet) falls back to (0, 0): visible but overlapping,
# rather than silently skipped.
monitor_pos() {
    local name="$1" axis="$2"
    jq -r --arg m "$name" --arg a "$axis" '.[$m][$a] // 0' <<<"$positions_json"
}

# ---- Applies every active monitor's real grid position/mode/scale in ONE
# atomic `hyprctl eval` call (every `hl.monitor()` statement joined by
# ";", one Lua chunk) -- not one hyprctl call per monitor like earlier
# versions of this script. Each external's bitdepth/cm (SDR vs HDR) is
# reapplied from hdr_last_choice() (hdr-settings.sh) here -- i.e. whatever
# the user last picked via waybar/scripts/hdr.sh for THAT PHYSICAL SCREEN
# (keyed by description, survives connector renames), defaulting to SDR
# only the first time a screen is ever seen. This used to hardcode SDR
# unconditionally on every desktop/startup/reload/hotplug, silently
# undoing a manual HDR choice each time -- HDR itself is still never
# auto-*enabled* out of nowhere, only ever re-asserted once the user has
# actually turned it on once via hdr.sh.
# Every external shares the same scale (scale.json only has one
# "external" entry so far -- a 3rd+ screen with its own scale needs is a
# future extension, not requested yet).
#
# Why one call instead of several: Hyprland's own overlap detector (the
# on-screen "your monitor layout is invalid" warning) only ever
# validates monitors against each other as they stood at the START of
# one `hyprctl eval` invocation -- a monitor repositioned earlier IN THE
# SAME invocation no longer counts as being at its old spot for a
# statement later in that same invocation. So the classic trigger --
# `display-layout.sh swap`, which puts each active screen exactly where
# the OTHER one currently sits -- never has an observable moment where
# both occupy the same spot, as long as both statements are issued
# together. Confirmed live (grim before/after, no warning) rather than
# assumed.
#
# An EARLIER version of this script "fixed" the same warning by parking
# every about-to-be-active screen at a scratch position 100000px away
# first, then moving it to its real spot in a second pass. That's not
# needed at all any more -- a single atomic call already covers it, with
# a real advantage: nothing here is ever positioned anywhere other than
# its own final spot, not even for an instant. The old parking pass
# mattered because it could -- and once did -- fling a screen the user
# was actively looking at (cursor and all) to that scratch position,
# which is what actually froze the session hard enough to need a reboot
# (see git history). Batching removes that risk at the root instead of
# just narrowing it.
#
# Which monitors are CURRENTLY enabled -- read from the live monitor
# list, not from `active` (tonight's TARGET set). Only used for the
# "survivors" check right below: whether at least one currently-enabled
# screen is ALSO staying active tells us whether disabling the outgoing
# screen(s) can safely join the same atomic call as the block above, or
# has to wait (see that block's own comment on the one gap it leaves).
declare -A was_enabled
while IFS=$'\t' read -r n d; do
    was_enabled["$n"]="$( [[ "$d" == "false" ]] && echo true || echo false )"
done < <(jq -r '.[] | [.name, (.disabled | tostring)] | @tsv' <<<"$mons_json")
survivors=0
for n in "$internal" "${externals[@]}"; do
    if [[ "${active[$n]:-false}" == true && "${was_enabled[$n]:-false}" == true ]]; then
        survivors=$((survivors + 1))
    fi
done

# Deliberately leaves ONE gap normally: a screen on its way OUT is left
# for the disable loop further down, AFTER the workspace migration below
# (see that section's own comment for why) -- so its current spot can
# still, very rarely, coincide with an active screen's new one (e.g.
# both -> one-screen when the survivor's 1-screen spot is exactly where
# the outgoing screen was), and Hyprland's overlap warning can show for
# that one case. Including the outgoing screen's disable in this SAME
# atomic call would close it too, but ordinarily means disabling it
# before migration runs -- exactly the ordering that reintroduced the
# "fenêtres perdues/mal placées" bug migration was written to fix.
#
# EXCEPT when there are no survivors at all (`display-layout.sh apply`
# switching straight between the two solo modes, e.g. external-only ->
# internal-only): every workspace's target is then the SAME single
# surviving screen regardless of order, by construction -- there's no
# "which of several targets does this workspace belong on" ambiguity
# left for Hyprland's own disconnect-time reassignment to get wrong, so
# the bug above can't recur here. Confirmed live: real windows open,
# switched screens this way, they landed correctly with no extra
# migration needed. Folding the disable into this same atomic call closes
# the overlap warning for exactly the case that prompted this section --
# the classic default-(0,0)-vs-default-(0,0) solo swap.
outgoing_folded_json="{}"
apply_targets() {
    local n scale extra w h best_rr mode x y stmts="" desc want
    for n in "$internal" "${externals[@]}"; do
        [[ "${active[$n]:-false}" == true ]] || continue
        if [[ "$n" == "$internal" ]]; then
            scale="$int_scale"; extra=""
        else
            scale="$ext_scale"
            desc=$(jq -r --arg m "$n" '.[] | select(.name==$m) | .description // empty' <<<"$mons_json")
            want="$(hdr_last_choice "$desc")"
            extra=", $(hdr_extra_clause "$want")"
        fi
        w=$(jq -r --arg m "$n" '.[] | select(.name==$m) | .width'  <<<"$mons_json")
        h=$(jq -r --arg m "$n" '.[] | select(.name==$m) | .height' <<<"$mons_json")
        best_rr="$(best_refresh "$n")"
        mode="preferred"
        [[ -n "$best_rr" ]] && mode="${w}x${h}@${best_rr}"
        x="$(monitor_pos "$n" x)"; y="$(monitor_pos "$n" y)"
        stmts+="hl.monitor({ output = \"$n\", disabled = false, mode = \"$mode\", position = \"${x}x${y}\", scale = $scale$extra }); "
    done
    if [[ "$survivors" -eq 0 ]]; then
        for n in "$internal" "${externals[@]}"; do
            if [[ "${was_enabled[$n]:-false}" == true && "${active[$n]:-false}" != true ]]; then
                stmts+="hl.monitor({ output = \"$n\", disabled = true }); "
                outgoing_folded_json="$(jq --arg n "$n" '. + {($n): true}' <<<"$outgoing_folded_json")"
            fi
        done
    fi
    [[ -n "$stmts" ]] && hyprctl eval "$stmts" >/dev/null
}
apply_targets

# ---- Force-migrates already-open workspaces to their new target monitor,
#      BEFORE the losing monitor gets disabled below ---------------------
# hl.workspace_rule() (below) only sets a PREFERENCE for where a
# workspace opens in the FUTURE -- it doesn't reliably drag an already-
# populated workspace's live windows over the moment the rule changes.
# That gap is exactly the "fenêtres perdues/mal placées" bug: toggling
# both -> internal-only -> both with windows already open flipped a
# workspace's rule to a new monitor, but its real content stayed parked
# on the old one (or wherever Hyprland's own disconnect-time fallback put
# it) until something else forced a resync. Same "don't trust the rule
# alone" lesson compact-workspaces.sh already learned for individual
# windows (see its own header comment) -- hl.dsp.workspace.move()
# (-> native moveworkspacetomonitor) instead relocates it right now,
# deterministically.
#
# Runs here, with both monitors still enabled, specifically so a
# workspace can be moved OFF the monitor that's about to be disabled a
# few lines down -- moving it after that disable would mean relying on
# Hyprland's own disconnect-time reassignment instead, which is exactly
# what isn't trusted here.
#
# Guarded to real work only: skips workspaces that don't exist yet,
# already sit on their target, or hold no real (non-dashboard) windows --
# an ordinary reload/reassert with nothing to migrate shouldn't yank
# focus or flicker a monitor for no reason.
workspaces_json="$(hyprctl workspaces -j)"
clients_json="$(hyprctl clients -j)"

migrate_workspace_if_needed() {
    local ws="$1" target="$2" cur has_windows
    cur="$(jq -r --argjson w "$ws" '.[] | select(.id==$w) | .monitor' <<<"$workspaces_json")"
    [[ -z "$cur" || "$cur" == "$target" ]] && return 0
    has_windows="$(jq -r --argjson w "$ws" \
        '[.[] | select(.workspace.id==$w and (.class | ascii_downcase | contains("dashboard") | not))] | length' \
        <<<"$clients_json")"
    [[ "$has_windows" -eq 0 ]] && return 0
    hyprctl eval "hl.dispatch(hl.dsp.workspace.move({ workspace = $ws, monitor = \"$target\" }))" >/dev/null
}

for i in 1 2 3 4 5; do migrate_workspace_if_needed "$i" "$range15_target"; done
for i in 6 7 8 9 10; do migrate_workspace_if_needed "$i" "$range610_target"; done

# ---- Turns off whatever's left to turn off, AFTER activating the others,
#      AFTER the migration above (see its own comment for why) ----------
# CRITICAL ORDER: disabling before enabling can momentarily pass through
# zero active screens (e.g. switching external-only -> internal-only),
# which makes Hyprland fall back to its headless fallback. On this 0.55.3
# build, this fallback causes a SEGV (see hyprlandCrashReport4932.txt:
# applyMonitorRule -> onDisconnect -> enterUnsafeState -> CHeadlessOutput::
# commit -> SEGV). Enabling first (apply_targets, above) guarantees at
# least one screen stays active at all times. One atomic call for every
# outgoing screen, same reasoning as apply_targets above -- excluding
# whichever ones apply_targets already folded into ITS atomic call
# (the no-survivors case, see its comment), which is most of them once a
# solo -> different-solo switch is routine rather than rare.
disable_stmts=""
for n in "$internal" "${externals[@]}"; do
    if [[ "${active[$n]}" != true ]] && [[ "$(jq -r --arg n "$n" '.[$n] // false' <<<"$outgoing_folded_json")" != true ]]; then
        disable_stmts+="hl.monitor({ output = \"$n\", disabled = true }); "
    fi
done
[[ -n "$disable_stmts" ]] && hyprctl eval "$disable_stmts" >/dev/null

# ---- Workspace assignment (1-5 / 6-10) -- range15_target/range610_target
#      were already resolved near the top (see comment there).
apply_workspace_rule() {
    local ws="$1" mon="$2"
    hyprctl eval "hl.workspace_rule({ workspace = \"$ws\", monitor = \"$mon\", persistent = true })" >/dev/null
}

for i in 1 2 3 4 5; do apply_workspace_rule "$i" "$range15_target"; done
for i in 6 7 8 9 10; do apply_workspace_rule "$i" "$range610_target"; done

# ---- Nudges Quickshell's workspace/monitor cache -----------------------
# Same quirk as compact-workspaces.sh (see its own comment on this exact
# line): hl.workspace_rule()/hl.monitor(), driven via `hyprctl eval`, don't
# emit anything on Hyprland's normal IPC event socket. Quickshell's
# Hyprland.workspaces model DOES receive the real monitor.added/
# monitor.removed events that trigger this script in the first place (see
# hypr/hyprland.lua), but not the workspace-monitor reassignment that
# follows -- so a bar sitting on a monitor that just changed role (e.g.
# workspace 8 moving from the now-unplugged external screen back onto the
# internal one) kept showing that workspace's pill on the wrong bar, or
# not highlighting it at all, until something else forced a resync. This
# is exactly the "need SUPER+C to make multi-monitor sort itself out"
# symptom -- compact-workspaces.sh's own refreshWorkspaces call was
# fixing it as an unrelated side effect.
#
# Retried, not fire-and-forget: on the hyprland.start path (see
# hypr/hyprland.lua), `quickshell -c bar` and this script are launched
# within the same synchronous exec-once block, microseconds apart -- but
# quickshell needs real wall-clock time afterwards to parse its QML and
# bind its "bar" IPC target, while this script reaches this line almost
# immediately (its own work above is just a handful of hyprctl/jq calls).
# A single `qs ipc call` fired that early hits no running instance yet
# and fails silently -- CONFIRMED via `qs -c bar ipc call bar
# refreshWorkspaces` against a not-yet-started/killed quickshell: exit
# 255, "No running instances for ... shell.qml" (a genuinely wrong
# target/function name against a LIVE instance, by contrast, still exits
# 0 -- so the exit code IS trustworthy here, just not against a live
# instance). Result: the bar's very first paint shows only whatever
# workspaces already existed natively (e.g. one per monitor, before this
# script's own consolidation) instead of the full persistent 1-10 set --
# and nothing retries it afterwards, since hl.workspace_rule() itself
# never emits the raw IPC event that shell.qml's onRawEvent fallback
# would otherwise catch (see shell.qml's own header comment on that
# handler). Retrying here for a few seconds covers exactly that gap;
# silently gives up (`|| true`) past the deadline -- still a no-op if
# quickshell isn't running/installed at all (waybar fallback, or between
# sessions), same as before.
for _ in $(seq 1 20); do
    qs -c bar ipc call bar refreshWorkspaces >/dev/null 2>&1 && break
    sleep 0.25
done || true

# ---- Hands focus back to whoever had it before the migration step above
#      possibly switched a monitor's visible workspace out from under it.
if [[ -n "$pre_focused_monitor" && -n "$pre_focused_ws" ]]; then
    hyprctl eval "hl.dispatch(hl.dsp.focus({ workspace = \"$pre_focused_ws\" }))" >/dev/null 2>&1 || true
fi
