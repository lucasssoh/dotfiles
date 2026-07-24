#!/usr/bin/env bash
set -euo pipefail

# =========================================================
# orbit-toggle.sh <tab> — bascule Orbit sur l'onglet donné (wifi|bluetooth),
# en fermant d'abord swaync s'il est ouvert -- les deux panneaux occupent le
# même coin (haut-droit) et ne doivent jamais être ouverts en même temps.
# =========================================================

# ~/.local/bin (où install.sh place orbit) n'est pas dans le PATH des
# processus lancés par Hyprland -- seul le profil zsh l'ajoute, donc `orbit`
# est introuvable ici sans ça (le clic ne faisait rien, silencieusement).
export PATH="$HOME/.local/bin:$PATH"

swaync-client -cp >/dev/null 2>&1 || true
orbit toggle --tab "${1:?usage: orbit-toggle.sh <wifi|bluetooth>}"
