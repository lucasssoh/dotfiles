#!/usr/bin/env bash
# scripts/hardware-detect.sh — CLI front-end to scripts/lib/hardware.sh.
#
# Installs nothing, needs no sudo, touches nothing. It exists so the
# detection can be inspected on its own -- before an install, on a machine
# you're about to migrate to, or when adding a new CPU generation to the
# table and wanting to check it classifies correctly.
#
#   ./scripts/hardware-detect.sh              # report + packages + notes
#   ./scripts/hardware-detect.sh --packages   # bare list, one per line
#   ./scripts/hardware-detect.sh --notes      # manual follow-ups only
#   ./scripts/hardware-detect.sh --json       # machine-readable
#
# --packages is the contract setup_fedora.sh consumes; keep it parseable
# (no colors, no headers, nothing but package names).
set -Eeuo pipefail

BOLD="\e[1m"; GREEN="\e[32m"; YELLOW="\e[33m"; BLUE="\e[34m"; RESET="\e[0m"

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib/hardware.sh
source "$DOTFILES_DIR/scripts/lib/hardware.sh"

usage() {
    cat <<'EOF'
Usage: hardware-detect.sh [--report|--packages|--notes|--json|--help]

  --report     (default) human-readable summary + packages + notes
  --packages   one Fedora package name per line, nothing else
  --notes      only the manual follow-ups (NVIDIA, vendor quirks, ...)
  --json       machine-readable detection result
EOF
}

# JSON by hand rather than via jq: this script must stay usable on a
# freshly installed system where jq isn't in yet (it's installed by the
# Hyprland module, which runs much later).
emit_json() {
    hw_detect
    local gpus="" g first=1
    for g in ${HW_GPUS[@]+"${HW_GPUS[@]}"}; do
        [ "$first" = 1 ] && first=0 || gpus+=", "
        gpus+="\"$g\""
    done

    local pkgs="" p
    first=1
    while IFS= read -r p; do
        [ -z "$p" ] && continue
        [ "$first" = 1 ] && first=0 || pkgs+=", "
        pkgs+="\"$p\""
    done < <(hw_packages)

    local swaps="" from to
    first=1
    while read -r from to; do
        [ -z "$from" ] && continue
        [ "$first" = 1 ] && first=0 || swaps+=", "
        swaps+="{\"from\": \"$from\", \"to\": \"$to\"}"
    done < <(hw_codec_swaps)

    cat <<EOF
{
  "cpu": {
    "vendor": "$HW_CPU_VENDOR",
    "family": ${HW_CPU_FAMILY:-null},
    "model": ${HW_CPU_MODEL:-null},
    "name": "$HW_CPU_NAME",
    "uarch": "$HW_CPU_UARCH",
    "profile": "$HW_CPU_PROFILE",
    "known": "$HW_CPU_KNOWN"
  },
  "gpus": [$gpus],
  "machine": {
    "vendor": "$HW_SYS_VENDOR",
    "product": "$HW_PRODUCT",
    "laptop": $([ "$HW_IS_LAPTOP" = yes ] && echo true || echo false)
  },
  "packages": [$pkgs],
  "codec_swaps": [$swaps]
}
EOF
}

emit_report() {
    hw_detect
    echo -e "\n${BOLD}── Hardware ──${RESET}\n"
    hw_report

    echo -e "\n${BOLD}── Packages for this machine ──${RESET}\n"
    hw_packages | sed 's/^/  /'

    # Listed apart from the packages above because they are not installed
    # the same way: these come from RPM Fusion and replace a package
    # Fedora already shipped. Printed as "from → to" for that reason.
    local swaps
    swaps="$(hw_codec_swaps)"
    if [ -n "$swaps" ]; then
        echo -e "\n${BOLD}── Codec swaps (RPM Fusion) ──${RESET}\n"
        echo "$swaps" | while read -r from to; do
            printf '  %s → %s\n' "$from" "$to"
        done
    fi

    local notes
    notes="$(hw_notes)"
    if [ -n "$notes" ]; then
        echo -e "\n${BOLD}── Manual follow-ups ──${RESET}\n"
        echo "$notes" | sed 's/^/  /'
    fi
    echo
}

case "${1:---report}" in
    --report)   emit_report ;;
    --packages) hw_packages ;;
    --notes)    hw_notes ;;
    --json)     emit_json ;;
    -h|--help)  usage ;;
    *)          echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
esac
