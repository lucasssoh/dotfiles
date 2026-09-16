#!/usr/bin/env bash
# pkg.sh — one way to ask for a package, across three distros and two
# privilege scopes.
#
# What this replaces: every config/*/install.sh carried its own three-way
# `dnf`/`pacman`/`apt-get` branch, 83 `sudo` call sites in all. Most of them
# ran unconditionally -- `sudo dnf install -y tmux wl-clipboard` on a machine
# that has had tmux for a year still wakes dnf, refreshes metadata, and asks
# for a password. That is the single reason `cc-pkg-mng update` could not
# promise never to prompt.
#
# The fix is to ask the *query* tool first. `rpm -q` needs no root and takes
# milliseconds; the package manager is only ever invoked for names that are
# genuinely absent. On a provisioned machine that is zero invocations and
# therefore zero password prompts.
#
# Two scopes:
#   CCPKG_ALLOW_ROOT=1 (default)  may install. This is what a module run
#                                 directly does -- scripts/lib/status.sh's
#                                 header promises every module stays usable
#                                 on its own, and that must keep being true.
#   CCPKG_ALLOW_ROOT=0            user scope. Missing packages are DEFERRED:
#                                 recorded, reported, and the module carries
#                                 on with its symlink/build work. Set by
#                                 `cc-pkg-mng update` without --system.

[ -n "${_PKG_SH_LOADED:-}" ] && return 0
_PKG_SH_LOADED=1

: "${STATE_DIR:=${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles}"
: "${CCPKG_ALLOW_ROOT:=1}"
# Which module is asking, for the ledgers. The runner exports it; a module run
# by hand falls back to its own directory name.
: "${CCPKG_MODULE:=$(basename "$(dirname "$(readlink -f "${BASH_SOURCE[1]:-$0}")")")}"

PKG_LEDGER="$STATE_DIR/packages.ledger"
PKG_DEFERRED="$STATE_DIR/deferred.ledger"

_pkg_info() { if declare -F info >/dev/null; then info "$@"; else echo "[INFO]  $*"; fi; }
_pkg_ok()   { if declare -F ok   >/dev/null; then ok   "$@"; else echo "[ OK ]  $*"; fi; }
_pkg_warn() { if declare -F warn >/dev/null; then warn "$@"; else echo "[WARN]  $*" >&2; fi; }

# pkg_mgr -> dnf | pacman | apt | none
pkg_mgr() {
    if   command -v dnf     >/dev/null 2>&1; then printf 'dnf'
    elif command -v pacman  >/dev/null 2>&1; then printf 'pacman'
    elif command -v apt-get >/dev/null 2>&1; then printf 'apt'
    else printf 'none'
    fi
}

# pkg_pick <dnf-name> <pacman-name> <apt-name> -> the name for THIS distro.
#
# This is what lets a module drop its three-way branch even when the package
# is spelled differently everywhere:
#     pkg_ensure fzf ripgrep "$(pkg_pick fd-find fd fd-find)"
pkg_pick() {
    case "$(pkg_mgr)" in
        dnf)    printf '%s' "$1" ;;
        pacman) printf '%s' "$2" ;;
        apt)    printf '%s' "${3:-$1}" ;;
        *)      printf '%s' "$1" ;;
    esac
}

# pkg_installed <name> -- no root, no network, fast.
pkg_installed() {
    case "$(pkg_mgr)" in
        dnf)    rpm -q "$1" >/dev/null 2>&1 ;;
        pacman) pacman -Q "$1" >/dev/null 2>&1 ;;
        apt)    dpkg -s "$1" >/dev/null 2>&1 ;;
        *)      return 1 ;;
    esac
}

# Both ledgers create their own parent from the path they are about to write,
# not from $STATE_DIR read again at call time. The two can disagree: the
# ledger paths are resolved once when this file is sourced, while STATE_DIR is
# an ordinary variable a caller may set only for the duration of the `source`.
# Deriving the directory from the file removes the question entirely.
_pkg_record() {
    mkdir -p "$(dirname "$PKG_LEDGER")"
    printf '%s\t%s\n' "$CCPKG_MODULE" "$1" >> "$PKG_LEDGER"
}

_pkg_defer() {
    mkdir -p "$(dirname "$PKG_DEFERRED")"
    printf '%s\t%s\n' "$CCPKG_MODULE" "$1" >> "$PKG_DEFERRED"
}

# pkg_ensure <name>...
#
# Records every name in the ledger whether or not it had to be installed: the
# ledger is what `verify` reads to answer "is everything this machine was told
# to have actually here?", and a package that was already present is still
# something this module depends on.
#
# Returns 0 even when packages were deferred. A deferral is not a failure --
# the module's real work (symlinks, config, builds) is still worth doing, and
# the run summary reports the deferrals separately.
pkg_ensure() {
    [ $# -gt 0 ] || return 0

    local mgr; mgr="$(pkg_mgr)"
    if [ "$mgr" = none ]; then
        _pkg_warn "no supported package manager — cannot install: $*"
        return 0
    fi

    local p missing=()
    for p in "$@"; do
        _pkg_record "$p"
        pkg_installed "$p" || missing+=("$p")
    done

    if [ "${#missing[@]}" -eq 0 ]; then
        _pkg_info "packages: already present (${#@}) — nothing to install."
        return 0
    fi

    if [ "$CCPKG_ALLOW_ROOT" != 1 ]; then
        for p in "${missing[@]}"; do _pkg_defer "$p"; done
        _pkg_warn "deferred (needs --system): ${missing[*]}"
        return 0
    fi

    _pkg_info "installing: ${missing[*]}"
    case "$mgr" in
        dnf)    sudo dnf install -y "${missing[@]}" ;;
        pacman) sudo pacman -S --noconfirm --needed "${missing[@]}" ;;
        apt)    sudo apt-get install -y "${missing[@]}" ;;
    esac || { _pkg_warn "install failed: ${missing[*]}"; return 1; }

    # dnf's --skip-unavailable (and apt's own quiet skips) can report success
    # while silently dropping a name. Naming what did not land is the pattern
    # scripts/install-hardware.sh:50-59 already uses, for exactly this reason.
    local still=()
    for p in "${missing[@]}"; do pkg_installed "$p" || still+=("$p"); done
    [ "${#still[@]}" -gt 0 ] && _pkg_warn "requested but not installed: ${still[*]}"
    return 0
}

# sudo_maybe <command>...
#
# For root-owned side effects that are not package installs (systemctl on the
# system bus, writing under /etc, udevadm). Deferred in user scope rather than
# prompting.
sudo_maybe() {
    if [ "$CCPKG_ALLOW_ROOT" = 1 ]; then
        sudo "$@"
    else
        _pkg_defer "cmd: $*"
        _pkg_warn "deferred (needs --system): sudo $*"
        return 0
    fi
}
