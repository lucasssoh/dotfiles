#!/usr/bin/env bash
set -euo pipefail

# =========================================================
# workspace-manager.sh — moteur unique : écrans actifs, position,
# alignement et refresh rate max, résolus par RÔLE (jamais par nom
# de connecteur — les noms peuvent changer d'un branchement à
# l'autre, ex. DP-2 devenu DP-9 en cours de session). L'externe est
# toujours mis en SDR ici : le HDR n'est jamais auto-appliqué, c'est
# un choix manuel via waybar/scripts/hdr.sh (cf. plus bas).
#
#   Interne  = 1er moniteur dont le nom matche eDP*/LVDS*/DSI*
#   Externe  = 1er moniteur restant, dans l'ordre de `hyprctl monitors`
#
#   Workspaces 1-7  -> interne (ou externe si interne inactif)
#   Workspaces 8-10 -> externe (ou interne si externe inactif/absent)
#
# La disposition voulue (quels écrans utiliser, lequel est à gauche,
# comment ils s'alignent) est lue depuis un état JSON persistant —
# même pattern que le système de wallpapers (set_wallpaper.sh /
# restore_wallpaper.sh + wallpaper-playlist.json) :
#
#   ~/.config/hypr/display-layout.json
#   { "mode": "both"|"internal"|"external",
#     "position": "external-left"|"external-right",
#     "align": "center"|"top"|"bottom" }
#
# Écrit par scripts/display-layout.sh (menu rofi / module waybar).
# Absent ou invalide -> défaut both / external-left / center.
#
# Idempotent : ne fait que rejouer des `hyprctl eval` déterministes
# à partir de l'état courant + du fichier JSON — relançable sans
# effet de bord. Appelé par les hooks hyprland.start / config.reloaded
# / monitor.added / monitor.removed (hypr/hyprland.lua).
#
# NB : ce setup charge sa config via un binding Lua custom (hl.*),
# ce qui bascule Hyprland sur un parser "non-legacy" où `hyprctl
# keyword` est refusé ("keyword can't work with non-legacy parsers.
# Use eval."). On pilote donc tout via `hyprctl eval '<lua hl.*>'`,
# qui appelle exactement les mêmes fonctions que hypr/monitors.lua.
# =========================================================

STATE_FILE="$HOME/.config/hypr/display-layout.json"
SCALE_STATE_FILE="$HOME/.config/hypr/scale.json"

# ---- Disposition voulue (état persistant, défauts si absent/invalide) ----
layout_mode="both"
layout_position="external-left"
layout_align="center"
if [[ -f "$STATE_FILE" ]]; then
    v="$(jq -r '.mode // empty'     "$STATE_FILE" 2>/dev/null || true)"
    if [[ "$v" =~ ^(both|internal|external)$ ]]; then layout_mode="$v"; fi
    v="$(jq -r '.position // empty' "$STATE_FILE" 2>/dev/null || true)"
    if [[ "$v" =~ ^(external-left|external-right)$ ]]; then layout_position="$v"; fi
    v="$(jq -r '.align // empty'    "$STATE_FILE" 2>/dev/null || true)"
    if [[ "$v" =~ ^(center|top|bottom)$ ]]; then layout_align="$v"; fi
fi

# ---- Scale voulu par rôle (état persistant, défauts si absent/invalide) ----
# Écrit par waybar/scripts/scale.sh (module par écran, cf. hdr.sh). Toujours
# par RÔLE, jamais par nom de connecteur -- mêmes garanties que ci-dessus.
INT_SCALE="1"
EXT_SCALE="1.25"
if [[ -f "$SCALE_STATE_FILE" ]]; then
    v="$(jq -r '.internal // empty' "$SCALE_STATE_FILE" 2>/dev/null || true)"
    if [[ -n "$v" ]]; then INT_SCALE="$v"; fi
    v="$(jq -r '.external // empty' "$SCALE_STATE_FILE" 2>/dev/null || true)"
    if [[ -n "$v" ]]; then EXT_SCALE="$v"; fi
fi

# ---- Tous les moniteurs connectés, y compris désactivés ----------------
# ("monitors -j" seul EXCLUT les écrans désactivés — indispensable pour
# résoudre les rôles/modes même quand un écran a été éteint par un choix
# de mode précédent.)
mons_json="$(hyprctl monitors all -j)"

# ---- Résolution des rôles ------------------------------------------------

# Connecteur de la dalle interne lu depuis DRM : persiste même quand la dalle
# est éteinte/désactivée (contrairement à `hyprctl monitors`, qui la perd dès
# qu'elle est hors ligne -- bug vécu en prod : mode "externe seul" -> dalle
# éteinte -> disparue de `mons_json` -> repli ci-dessous la reclassait comme
# interne l'écran externe -> plus aucun moyen de revenir en arrière). Dynamique
# (suit le connecteur réel), jamais codé en dur.
internal_from_drm() {
    local d
    # 1) connecteur interne CONNECTÉ = la dalle réelle de ce boot (gère le MUX
    #    double-GPU : la dalle peut apparaître sur card1-eDP-* ou card2-eDP-*
    #    selon le routage au démarrage -- bug vécu en prod : prendre le 1er
    #    connecteur du glob sans vérifier son status pouvait pointer sur un
    #    connecteur fantôme d'un GPU non utilisé ce boot).
    for d in /sys/class/drm/card*-eDP-* /sys/class/drm/card*-LVDS-* /sys/class/drm/card*-DSI-*; do
        [[ -e "$d" ]] || continue
        [[ "$(cat "$d/status" 2>/dev/null)" == connected ]] || continue
        basename "$d" | sed -E 's/^card[0-9]+-//'
        return 0
    done
    # 2) repli : n'importe quel connecteur interne (dalle éteinte/désactivée
    #    mais toujours la nôtre) -- évite le deadlock "externe-seul".
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
    # Aucune dalle laptop détectée (poste fixe) : repli sur le 1er moniteur listé
    internal="$(jq -r '.[0].name // empty' <<<"$mons_json")"
fi
[[ -z "$internal" ]] && { echo "workspace-manager: aucun moniteur détecté" >&2; exit 0; }

first_external="$(jq -r --arg m "$internal" '[.[] | select(.name != $m)][0].name // empty' <<<"$mons_json")"

# ---- Résolution des écrans actifs selon le mode voulu (+ garde-fous) ---
active_internal=true
active_external=true
case "$layout_mode" in
    internal) active_external=false ;;
    external) active_internal=false ;;
esac
[[ -z "$first_external" ]] && active_external=false   # pas d'externe connecté -> ne peut pas être actif
if [[ "$active_internal" != true && "$active_external" != true ]]; then
    active_internal=true   # jamais zéro écran actif : repli sur l'interne
fi

# ---- Helper : meilleur taux de rafraîchissement dispo à la résolution
#      native courante de l'écran (jamais codé en dur — dépend du panneau) ----
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

# ---- Position / alignement (coordonnées logiques = pixels ÷ scale) -----
# L'interne est à INT_SCALE, l'externe à EXT_SCALE — mêmes valeurs que
# celles qu'on va appliquer plus bas.
int_w=$(jq -r --arg m "$internal" '.[] | select(.name==$m) | .width'  <<<"$mons_json")
int_h=$(jq -r --arg m "$internal" '.[] | select(.name==$m) | .height' <<<"$mons_json")
int_lw=$(jq -n --argjson w "$int_w" --argjson s "$INT_SCALE" '($w / $s) | floor')
int_lh=$(jq -n --argjson h "$int_h" --argjson s "$INT_SCALE" '($h / $s) | floor')
int_x=0
int_y=0

if [[ -n "$first_external" ]]; then
    ext_w=$(jq -r --arg m "$first_external" '.[] | select(.name==$m) | .width'  <<<"$mons_json")
    ext_h=$(jq -r --arg m "$first_external" '.[] | select(.name==$m) | .height' <<<"$mons_json")
    ext_lw=$(jq -n --argjson w "$ext_w" --argjson s "$EXT_SCALE" '($w / $s) | floor')
    ext_lh=$(jq -n --argjson h "$ext_h" --argjson s "$EXT_SCALE" '($h / $s) | floor')
    ext_x=0
    ext_y=0
fi

if [[ "$active_internal" == true && "$active_external" == true ]]; then
    if [[ "$layout_position" == "external-left" ]]; then
        ext_x=0; int_x=$ext_lw
    else
        int_x=0; ext_x=$int_lw
    fi
    max_h=$(( int_lh > ext_lh ? int_lh : ext_lh ))
    case "$layout_align" in
        top)    int_y=0; ext_y=0 ;;
        bottom) int_y=$(( max_h - int_lh )); ext_y=$(( max_h - ext_lh )) ;;
        *)      int_y=$(( (max_h - int_lh) / 2 )); ext_y=$(( (max_h - ext_lh) / 2 )) ;;
    esac
fi
# Un seul écran actif -> déjà x=0/y=0 par défaut ci-dessus, rien à faire de plus.

# ---- Applique l'interne (si actif) --------------------------------------
if [[ "$active_internal" == true ]]; then
    best_rr="$(best_refresh "$internal")"
    int_mode="preferred"
    [[ -n "$best_rr" ]] && int_mode="${int_w}x${int_h}@${best_rr}"
    hyprctl eval "hl.monitor({ output = \"$internal\", disabled = false, mode = \"$int_mode\", position = \"${int_x}x${int_y}\", scale = ${INT_SCALE} })" >/dev/null
fi

# ---- Applique l'externe (si actif) : refresh max, toujours en SDR -------
# SDR est TOUJOURS le défaut ici (bureau, démarrage, reload, hotplug) : le HDR
# n'est jamais auto-appliqué, sous peine de fausser les couleurs de tout
# contenu non-HDR. Le HDR est un choix strictement manuel de l'utilisateur,
# activé à la demande pour du contenu multimédia via le module waybar dédié
# (waybar/scripts/hdr.sh toggle/menu) — indépendant de ce script.
if [[ "$active_external" == true ]]; then
    best_rr="$(best_refresh "$first_external")"
    ext_mode="preferred"
    [[ -n "$best_rr" ]] && ext_mode="${ext_w}x${ext_h}@${best_rr}"
    hyprctl eval "hl.monitor({ output = \"$first_external\", disabled = false, mode = \"$ext_mode\", position = \"${ext_x}x${ext_y}\", scale = ${EXT_SCALE}, bitdepth = 8, cm = \"auto\" })" >/dev/null
fi

# ---- Éteint l'écran non désiré, APRÈS avoir activé les autres ----------
# ORDRE CRITIQUE : si on désactivait avant d'activer, on peut passer par un
# instant à zéro écran actif (ex. bascule externe-seul -> interne-seul), ce
# qui fait basculer Hyprland sur son fallback headless — et ce fallback fait
# planter ce build 0.55.3 (SEGV confirmé, cf. hyprlandCrashReport4932.txt :
# applyMonitorRule -> onDisconnect -> enterUnsafeState -> CHeadlessOutput::
# commit -> SEGV). Activer d'abord garantit toujours >= 1 écran actif.
[[ "$active_internal" != true ]] && \
    hyprctl eval "hl.monitor({ output = \"$internal\", disabled = true })" >/dev/null
[[ -n "$first_external" && "$active_external" != true ]] && \
    hyprctl eval "hl.monitor({ output = \"$first_external\", disabled = true })" >/dev/null

# ---- Assignation des workspaces (1-7 / 8-10), repliées sur l'écran actif --
if [[ "$active_internal" == true && "$active_external" == true ]]; then
    int_target="$internal"; ext_target="$first_external"
elif [[ "$active_internal" == true ]]; then
    int_target="$internal"; ext_target="$internal"
else
    int_target="$first_external"; ext_target="$first_external"
fi

apply_workspace_rule() {
    local ws="$1" mon="$2"
    hyprctl eval "hl.workspace_rule({ workspace = \"$ws\", monitor = \"$mon\", persistent = true })" >/dev/null
}

for i in 1 2 3 4 5 6 7; do apply_workspace_rule "$i" "$int_target"; done
for i in 8 9 10;         do apply_workspace_rule "$i" "$ext_target"; done
