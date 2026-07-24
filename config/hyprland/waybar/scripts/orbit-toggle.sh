#!/usr/bin/env bash
set -euo pipefail

# =========================================================
# orbit-toggle.sh <tab> — bascule Orbit sur l'onglet donné (wifi|bluetooth),
# en fermant d'abord swaync s'il est ouvert -- les deux panneaux occupent le
# même coin (haut-droit) et ne doivent jamais être ouverts en même temps.
# =========================================================

swaync-client -cp >/dev/null 2>&1 || true
orbit toggle --tab "${1:?usage: orbit-toggle.sh <wifi|bluetooth>}"
