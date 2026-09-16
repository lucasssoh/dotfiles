#!/usr/bin/env bash
set -Eeuo pipefail

# The single safe_link (scripts/lib/link.sh). It replaces the copy that used
# to live here: that one removed and re-created the link on every run, even
# when it was already correct. This one returns early, and records what it
# did so `cc-pkg-mng verify` can check it later.
. "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../../scripts/lib/link.sh"

BLUE="\e[34m"
GREEN="\e[32m"
RESET="\e[0m"

info() { echo -e "${BLUE}[INFO]${RESET}  $*"; }
ok()   { echo -e "${GREEN}[ OK ]${RESET}  $*"; }

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DEST_DIR="$HOME/.config/ccnote"

info "Setting up the ccnote workflow..."

# 1. Create the destination folder under ~/.config
mkdir -p "$DEST_DIR"

# Helper to link cleanly

# 2. Symlink the Python script and the Zsh config
safe_link "$DOTFILES_DIR/config/ccnote/ccnote.py" "$DEST_DIR/ccnote.py"
safe_link "$DOTFILES_DIR/config/ccnote/ccnote.zsh" "$DEST_DIR/ccnote.zsh"

# Make the Python script executable at its source
chmod +x "$DOTFILES_DIR/config/ccnote/ccnote.py"

ok "ccnote module installed to $DEST_DIR"
echo ""
echo "To enable the command, add this line at the end of your ~/.zshrc or shell startup file:"
echo "   source ~/.config/ccnote/ccnote.zsh"
