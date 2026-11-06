#!/usr/bin/env bash
set -Eeuo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CCPKG_MODULE=oplide
. "$DOTFILES_DIR/scripts/lib/link.sh"

safe_link "$DOTFILES_DIR/config/oplide/oplide.desktop" \
    "$HOME/.local/share/applications/oplide.desktop"
