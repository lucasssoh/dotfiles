#!/usr/bin/env bash
set -euo pipefail

# =========================================================
# workspace-manager.sh — assignation workspaces + tuning écran
# externe, résolus par RÔLE (jamais par nom de connecteur).
#
#   Interne  = 1er moniteur dont le nom matche eDP*/LVDS*/DSI*
#   Externe  = tout le reste, dans l'ordre de `hyprctl monitors -j`
#
#   Workspaces 1-7  -> interne
#   Workspaces 8-10 -> 1er externe détecté, sinon interne (repli)
#
# Idempotent : ne fait que rejouer des `hyprctl eval` déterministes,
# sans état — relançable sans effet de bord.
#
# NB : ce setup charge sa config via un binding Lua custom (hl.*),
# ce qui bascule Hyprland sur un parser "non-legacy" où `hyprctl
# keyword` est refusé ("keyword can't work with non-legacy parsers.
# Use eval."). On pilote donc tout via `hyprctl eval '<lua hl.*>'`,
# qui appelle exactement les mêmes fonctions que hypr/monitors.lua.
# =========================================================

EXT_SCALE="1.2"
EXT_SDRBRIGHTNESS="1.2"
EXT_SDRSATURATION="1.0"
CACHE_DIR="${XDG_RUNTIME_DIR:-/tmp}/hdr-toggle"

mons_json="$(hyprctl monitors -j)"

# ---- Résolution des rôles --------------------------------------------

internal="$(jq -r '[.[] | select(.name | test("^(eDP|LVDS|DSI)"))][0].name // empty' <<<"$mons_json")"
if [[ -z "$internal" ]]; then
    # Aucune dalle laptop détectée (poste fixe) : repli sur le 1er moniteur listé
    internal="$(jq -r '.[0].name // empty' <<<"$mons_json")"
fi

[[ -z "$internal" ]] && { echo "workspace-manager: aucun moniteur détecté" >&2; exit 0; }

first_external="$(jq -r --arg m "$internal" '[.[] | select(.name != $m)][0].name // empty' <<<"$mons_json")"

# ---- Tuning de l'interne (refresh rate max dispo à la résolution native) ----
# Le catch-all générique de monitors.lua utilise mode="preferred", qui peut
# pointer vers un mode plus bas que le max réel du panneau (ex: 60Hz alors que
# 144Hz est disponible) — on résout donc le refresh max disponible ici, sans
# jamais coder le chiffre en dur (dépend du panneau, pas du connecteur).
int_json="$(jq -r --arg m "$internal" '.[] | select(.name==$m)' <<<"$mons_json")"
iw=$(jq -r '.width' <<<"$int_json")
ih=$(jq -r '.height' <<<"$int_json")
ix=$(jq -r '.x'      <<<"$int_json")
iy=$(jq -r '.y'      <<<"$int_json")

best_rr="$(jq -r --arg m "$internal" --argjson w "$iw" --argjson h "$ih" '
    .[] | select(.name==$m) | .availableModes[]?
    | select(startswith(($w|tostring) + "x" + ($h|tostring) + "@"))
    | capture("@(?<rr>[0-9.]+)Hz").rr | tonumber
' <<<"$mons_json" | sort -rn | head -1)"

if [[ -n "$best_rr" ]]; then
    hyprctl eval "hl.monitor({ output = \"$internal\", mode = \"${iw}x${ih}@${best_rr}\", position = \"${ix}x${iy}\", scale = 1 })" >/dev/null
fi

# ---- Assignation des workspaces ---------------------------------------

apply_workspace_rule() {
    local ws="$1" mon="$2"
    hyprctl eval "hl.workspace_rule({ workspace = \"$ws\", monitor = \"$mon\", persistent = true })" >/dev/null
}

for i in 1 2 3 4 5 6 7; do
    apply_workspace_rule "$i" "$internal"
done

ext_target="${first_external:-$internal}"
for i in 8 9 10; do
    apply_workspace_rule "$i" "$ext_target"
done

# ---- Tuning de l'externe (scale + HDR selon EDID) ----------------------

hdr_capable() {
    local m="$1" cache="$CACHE_DIR/cap-$m" edid="" path cap=1
    if [[ -f "$cache" ]]; then
        [[ "$(cat "$cache")" == "1" ]]; return
    fi
    mkdir -p "$CACHE_DIR"
    for path in /sys/class/drm/*-"$m"/edid; do
        [[ -e "$path" ]] && { edid="$path"; break; }
    done
    if [[ -n "$edid" ]] && command -v edid-decode >/dev/null 2>&1; then
        if edid-decode "$edid" 2>/dev/null \
             | grep -qiE 'HDR Static Metadata|SMPTE ST ?2084|ST2084'; then
            cap=1
        else
            cap=0
        fi
    fi
    echo "$cap" > "$cache"
    [[ "$cap" == "1" ]]
}

if [[ -n "$first_external" ]]; then
    m="$first_external"
    j="$(jq -r --arg m "$m" '.[] | select(.name==$m)' <<<"$mons_json")"
    w=$(jq -r '.width'        <<<"$j")
    h=$(jq -r '.height'       <<<"$j")
    rr=$(jq -r '.refreshRate' <<<"$j")
    x=$(jq -r '.x'            <<<"$j")
    y=$(jq -r '.y'            <<<"$j")
    rr=$(printf '%.2f' "$rr")
    mode="${w}x${h}@${rr}"
    position="${x}x${y}"

    if hdr_capable "$m"; then
        hyprctl eval "hl.monitor({ output = \"$m\", mode = \"$mode\", position = \"$position\", scale = ${EXT_SCALE}, bitdepth = 10, cm = \"hdr\", sdrbrightness = ${EXT_SDRBRIGHTNESS}, sdrsaturation = ${EXT_SDRSATURATION} })" >/dev/null
    else
        hyprctl eval "hl.monitor({ output = \"$m\", mode = \"$mode\", position = \"$position\", scale = ${EXT_SCALE}, bitdepth = 8, cm = \"auto\" })" >/dev/null
    fi
fi
