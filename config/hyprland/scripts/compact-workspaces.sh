#!/usr/bin/env bash
set -euo pipefail

# =========================================================
# compact-workspaces.sh — retasse les workspaces occupés vers le
# début de leur plage, PAR MONITEUR (jamais de mélange interne/
# externe : chaque moniteur ne compacte que dans ses propres
# workspaces, tels qu'assignés par workspace-manager.sh).
#
# Ex (interne 1-7) : 2, 3, 6 occupés -> compactés en 1, 2, 3.
#
# Déclenchement MANUEL uniquement (bind clavier) : ce build
# d'Hyprland expose une API Lua (hl.dsp.window.move) qui ne propose
# pas d'équivalent silencieux de movetoworkspacesilent — tout
# déplacement fait sauter l'écran sur le workspace cible. Le script
# referme la boucle en refocusant chaque moniteur sur son contenu
# d'origine (renuméroté si besoin) une fois tous les déplacements
# terminés.
# =========================================================

rules_json="$(hyprctl workspacerules -j)"
clients_json="$(hyprctl clients -j)"
monitors_json="$(hyprctl monitors -j)"

focused_monitor="$(jq -r '.[] | select(.focused==true) | .name' <<<"$monitors_json")"

move_window() {
    local addr="$1" target="$2"
    hyprctl eval "hl.dispatch(hl.dsp.window.move({ window = \"address:$addr\", workspace = \"$target\" }))" >/dev/null
}

refocus() {
    local ws="$1"
    hyprctl eval "hl.dispatch(hl.dsp.focus({ workspace = \"$ws\" }))" >/dev/null
}

mapfile -t monitor_names < <(jq -r '.[].name' <<<"$monitors_json")

declare -A restore_focus  # moniteur -> workspace à refocus en fin de script

for mon in "${monitor_names[@]}"; do
    mapfile -t slots < <(jq -r --arg m "$mon" \
        '[.[] | select(.monitor==$m) | (.workspaceString|tonumber)] | sort | .[]' <<<"$rules_json")
    [[ ${#slots[@]} -eq 0 ]] && continue

    slots_json="$(printf '%s\n' "${slots[@]}" | jq -R 'tonumber' | jq -s '.')"

    active_ws="$(jq -r --arg m "$mon" '.[] | select(.name==$m) | .activeWorkspace.id // empty' <<<"$monitors_json")"
    [[ -n "$active_ws" ]] && restore_focus["$mon"]="$active_ws"

    # workspaces occupés (fenêtres réelles, hors dashboard vide) parmi les
    # slots de ce moniteur, dans l'ordre ascendant des slots
    mapfile -t occ < <(jq -r --argjson slots "$slots_json" '
        ([.[] | select(.class | ascii_downcase | contains("dashboard") | not) | .workspace.id] | unique) as $busy
        | $slots[] | select(. as $s | $busy | index($s))
    ' <<<"$clients_json")

    for i in "${!occ[@]}"; do
        old="${occ[$i]}"
        new="${slots[$i]}"
        [[ "$old" == "$new" ]] && continue

        while IFS= read -r addr; do
            [[ -z "$addr" ]] && continue
            move_window "$addr" "$new"
        done < <(jq -r --argjson ws "$old" \
            '.[] | select(.workspace.id==$ws and (.class | ascii_downcase | contains("dashboard") | not)) | .address' \
            <<<"$clients_json")

        if [[ "${restore_focus[$mon]:-}" == "$old" ]]; then
            restore_focus["$mon"]="$new"
        fi
    done
done

# Refocus chaque moniteur sur son contenu d'origine (renuméroté si déplacé).
# Le moniteur qui avait le focus clavier au départ est refocusé en dernier,
# pour le lui restituer.
for mon in "${monitor_names[@]}"; do
    [[ "$mon" == "$focused_monitor" ]] && continue
    [[ -n "${restore_focus[$mon]:-}" ]] && refocus "${restore_focus[$mon]}"
done
[[ -n "${restore_focus[$focused_monitor]:-}" ]] && refocus "${restore_focus[$focused_monitor]}"
