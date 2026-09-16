#!/usr/bin/env bash
# link.sh — THE safe_link, and the ledger that lets `verify` check its work.
#
# Before this file, `safe_link` was defined fourteen times across the modules,
# in four different implementations:
#
#   * ten byte-identical copies of a 7-line version that `rm`s the link and
#     re-creates it on every single run, whether or not it was already right;
#   * one with extra blank lines (mangohud);
#   * liseuse's, which tests `-e` instead of `-f` and will therefore happily
#     `rm -rf` a real directory sitting at the destination;
#   * wireplumber's one-line compound;
#
# and five modules defined none at all, using raw `ln -sf` or `ln -sfn`.
#
# The version kept here is config/hyprland/install.sh's, which was the only
# one that is genuinely a no-op on re-run: it compares where the link already
# points and returns early. That property is what makes `cc-pkg-mng update`
# quiet -- twelve modules re-creating every link on every run produced twelve
# screens of "Linked:" for a machine where nothing had changed.
#
# It also backs a real file or directory up to .bak instead of deleting it,
# which is the behaviour you want the first time a module takes over a path
# you had configured by hand.

[ -n "${_LINK_SH_LOADED:-}" ] && return 0
_LINK_SH_LOADED=1

: "${STATE_DIR:=${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles}"
: "${CCPKG_MODULE:=unknown}"
LINK_LEDGER="$STATE_DIR/links.ledger"

_link_info() { if declare -F info >/dev/null; then info "$@"; else echo "[INFO]  $*"; fi; }
_link_ok()   { if declare -F ok   >/dev/null; then ok   "$@"; else echo "[ OK ]  $*"; fi; }
_link_warn() { if declare -F warn >/dev/null; then warn "$@"; else echo "[WARN]  $*" >&2; fi; }

# The ledger is written by safe_link AS IT RUNS, rather than being a second
# list of expected links maintained by hand next to the real ones. A hand-kept
# list is exactly the kind of thing that drifts -- see what happened to the
# MODULES array. This records what actually happened.
_link_record() {
    mkdir -p "$(dirname "$LINK_LEDGER")"
    # Rewrite any previous entry for this destination so the ledger holds one
    # line per path, not one per run.
    if [ -f "$LINK_LEDGER" ]; then
        local tmp="$LINK_LEDGER.tmp.$$"
        awk -F'\t' -v d="$2" '$3 != d' "$LINK_LEDGER" > "$tmp" 2>/dev/null && mv -f "$tmp" "$LINK_LEDGER"
    fi
    printf '%s\t%s\t%s\n' "$CCPKG_MODULE" "$1" "$2" >> "$LINK_LEDGER"
}

# safe_link <src> <dst>
#   src  absolute path inside the repo
#   dst  absolute path where the symlink should live
safe_link() {
    local src="$1" dst="$2"

    _link_record "$src" "$dst"

    # Already the right link: say nothing loud and return. This early exit is
    # the whole reason this implementation was the one worth keeping.
    if [ -L "$dst" ] && [ "$(readlink -f "$dst")" = "$(readlink -f "$src")" ]; then
        _link_info "Already linked: $dst"
        return 0
    fi

    # A real file or directory (not a symlink) is backed up, never removed.
    if [ -e "$dst" ] && [ ! -L "$dst" ]; then
        _link_warn "Backing up existing: $dst → $dst.bak"
        mv "$dst" "$dst.bak"
    fi

    # A symlink pointing somewhere else is stale; drop it.
    [ -L "$dst" ] && rm -f "$dst"

    mkdir -p "$(dirname "$dst")"
    ln -s "$src" "$dst"
    _link_ok "Linked: $dst → $src"
}
