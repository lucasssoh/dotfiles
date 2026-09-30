# units/lib/hook.sh — sourced by every hook script.
#
# A hook runs as the user, stdin closed, from the repo root, with:
#   COUCOU_DIR          the checkout
#   CCPKG_UNIT          the unit it belongs to
#   CCPKG_HOOK_STATE    a directory it may keep its own state in
#   CCPKG_ANSWER_<ID>   one per answered question of the unit
# A hook declared run_as = "root" calls `as_root` for its system steps; the
# manager holds the sudo session for the whole run.
set -Eeuo pipefail

REPO="${COUCOU_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
HOOK_STATE="${CCPKG_HOOK_STATE:-${XDG_STATE_HOME:-$HOME/.local/state}/coucou-shell/hooks/${CCPKG_UNIT:-manual}}"
mkdir -p "$HOOK_STATE"

info() { echo "[INFO]  $*"; }
ok()   { echo "[ OK ]  $*"; }
warn() { echo "[WARN]  $*" >&2; }

as_root() { sudo -n "$@"; }

have() { command -v "$1" >/dev/null 2>&1; }

# Under pipefail, `cmd | grep -q` fails even on a match: grep exits at the
# first one and cmd dies of SIGPIPE. Hooks write `cmd | grep ... >/dev/null`.

# One-time marker: `once NAME || exit 0` skips a step already done.
once() { [ ! -e "$HOOK_STATE/$1.done" ]; }
done_once() { touch "$HOOK_STATE/$1.done"; }
