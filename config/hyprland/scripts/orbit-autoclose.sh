#!/usr/bin/env bash
set -uo pipefail

# =========================================================
# orbit-autoclose.sh — ferme Orbit dès qu'une autre fenêtre prend le focus
# (comme swaync, dont le panneau se ferme nativement au clic en dehors).
#
# Orbit est une simple surface layer-shell : GTK/gtk4-layer-shell n'émet
# jamais de perte de focus pour ce genre de surface (testé en live -- la
# propriété "is-active" ne passe à faux à aucun moment quand on bascule
# vers une autre appli). On s'appuie donc directement sur les événements
# Hyprland (activewindow), qui eux sont fiables. Vérifié aussi : ouvrir
# Orbit lui-même ne déclenche AUCUN événement activewindow (les surfaces
# layer-shell n'apparaissent pas dans ce flux) -- donc aucun risque que ce
# script referme Orbit juste après l'avoir ouvert.
# =========================================================

# ~/.local/bin (où install.sh place orbit) n'est pas dans le PATH des
# processus lancés par Hyprland -- seul le profil zsh l'ajoute.
export PATH="$HOME/.local/bin:$PATH"

SOCKET=""
for _ in $(seq 1 30); do
    SOCKET=$(find "/run/user/$(id -u)/hypr/" -name ".socket2.sock" 2>/dev/null | head -1)
    [ -n "$SOCKET" ] && break
    sleep 1
done
[ -z "$SOCKET" ] && exit 1

socat -u UNIX-CONNECT:"$SOCKET" STDOUT | while IFS= read -r line; do
    case "$line" in
        activewindow\>\>*)
            orbit hide >/dev/null 2>&1 || true
            ;;
    esac
done
