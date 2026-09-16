#!/usr/bin/env bash
# ccpkg — puts `cc-pkg-mng` on PATH.
#
# A symlink, never a copy. That is the whole reason the manager is bash: the
# link points into the repo, so `git pull` makes the command current with
# nothing to rebuild and no bootstrap step. A copy would need re-copying after
# every pull, by the very tool that the pull just changed.
#
# The name is not `cc`, which is what was originally wanted: /usr/bin/cc is a
# symlink to gcc, and ~/.local/bin sits 2nd in this user's PATH against 10th
# for /usr/bin. A `cc` here would shadow the C compiler for the whole session
# -- `make` defaults CC to cc, and pip uses it to build native extensions.
set -Eeuo pipefail

. "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../../scripts/lib/link.sh"

GREEN="\e[32m"; YELLOW="\e[33m"; BLUE="\e[34m"; RESET="\e[0m"
info() { echo -e "${BLUE}[INFO]${RESET}  $*"; }
ok()   { echo -e "${GREEN}[ OK ]${RESET}  $*"; }
warn() { echo -e "${YELLOW}[WARN]${RESET}  $*" >&2; }

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

mkdir -p "$HOME/.local/bin"
chmod +x "$DOTFILES_DIR/bin/cc-pkg-mng"
safe_link "$DOTFILES_DIR/bin/cc-pkg-mng" "$HOME/.local/bin/cc-pkg-mng"

# Shadowing is the failure mode worth checking for here, given what the name
# had to avoid in the first place.
resolved="$(command -v cc-pkg-mng 2>/dev/null || true)"
if [ -n "$resolved" ] && [ "$resolved" != "$HOME/.local/bin/cc-pkg-mng" ]; then
    warn "cc-pkg-mng resolves to $resolved, not ~/.local/bin — PATH order?"
elif [ -z "$resolved" ]; then
    info "~/.local/bin is not on PATH yet — it is added by config/bash/.bashrc."
fi

ok "cc-pkg-mng installed."
