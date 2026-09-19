#!/usr/bin/env bash
# changes.sh — "has this part of the repo changed since we last applied it?"
#
# The answer is a content fingerprint per directory, persisted between runs
# (see state.sh). Three cheaper-looking approaches were rejected:
#
#   * A git SHA (`git rev-parse HEAD`) is blind to uncommitted edits -- which
#     is precisely the case this exists for ("j'ai mis a jour du config").
#   * `git diff --name-only OLD..NEW` needs a valid old SHA, breaks across
#     rebases, amends and shallow clones, and still ignores the worktree.
#   * mtimes lie. `cp`, `git checkout` and `git stash` all rewrite them, and
#     `cp -r` does not preserve them at all -- which is exactly how the old
#     Rust build path defeated cargo's own fingerprinting. This repo already
#     rejected mtimes once for the same class of reason, in
#     config/hyprland/scripts/wallpaper-cache-watcher.sh:84-101.
#
# The file list comes from `git ls-files`, which buys .gitignore handling for
# free: config/hyprland/balise-src/target/ (563 MB) is excluded without a
# single hand-written exclusion, and so are __pycache__/ and the runtime
# *.json under hypr/. Untracked-but-not-ignored files DO count, so a new file
# you have not committed yet still triggers a re-apply.
#
# Measured on this repo: fingerprinting all 19 module directories takes about
# 145 ms total, so this is cheap enough to run on every invocation.

[ -n "${_CHANGES_SH_LOADED:-}" ] && return 0
_CHANGES_SH_LOADED=1

# dotfiles_root — the repo this file lives in, resolved through symlinks
# (bin/cc-pkg-mng is symlinked into ~/.local/bin, so $0 is not in the repo).
dotfiles_root() {
    if [ -z "${DOTFILES_ROOT:-}" ]; then
        local self
        self="$(readlink -f "${BASH_SOURCE[0]}")"
        DOTFILES_ROOT="$(cd "$(dirname "$self")/../.." && pwd)"
    fi
    printf '%s' "$DOTFILES_ROOT"
}

# fp_path <path> -> 64 hex chars, or "empty"
#
# <path> may be absolute or relative to the repo root, and may name a
# directory or a single file.
#
# The file LIST is hashed alongside the file CONTENTS on purpose: hashing
# contents alone would miss a deletion or a rename, since no surviving file's
# bytes change. Sorting makes the result independent of git's output order.
fp_path() {
    local root target list
    root="$(dotfiles_root)"
    target="$1"
    # Normalise an absolute path inside the repo back to a relative one, so
    # callers may pass either.
    case "$target" in
        "$root"/*) target="${target#"$root"/}" ;;
    esac

    list="$(git -C "$root" ls-files --cached --others --exclude-standard -- "$target" 2>/dev/null | LC_ALL=C sort)"
    if [ -z "$list" ]; then
        printf 'empty'
        return 0
    fi

    {
        printf '%s\n' "$list"
        printf '%s\n' "$list" | tr '\n' '\0' \
            | ( cd "$root" && xargs -0 -r sha256sum 2>/dev/null )
    } | sha256sum | cut -d' ' -f1
}

# path_target <repo-relative path> -> one of
#   module:<name>   this module's install.sh applies it
#   phase:system    setup_fedora.sh territory (needs root)
#   phase:hardware  the hardware phase (needs root)
#   meta:manager    changes how the NEXT run behaves; nothing to "apply"
#   none            documentation and assets nothing consumes at install time
#   unmapped        nobody claims it -- reported, never silently ignored
#
# First match wins, so the order of the cases below is the specificity order.
# `scripts/lib/hardware.sh` in particular has to be tested before the generic
# `scripts/lib/*.sh` rule that would otherwise swallow it.
#
# `meta:manager` deliberately triggers nothing. Editing install_all.sh or one
# of these libraries changes how the next run behaves; the scripts are read
# fresh from disk every time, so there is no "apply" step to perform.
# Re-running 19 modules because a comment moved in status.sh is exactly the
# kind of noise that teaches people to stop trusting a tool.
#
# `unmapped` is a first-class outcome, not a default. It is what keeps this
# table honest as the repo grows: `status` lists unmapped paths so a new
# top-level directory cannot quietly fall outside the manager's world. Same
# philosophy as scripts/check-deps.sh, which exists precisely because silent
# gaps cost hours.
# _module_owning <repo-relative path under config/> -> module name
#
# Modules are normally config/<name>/, but may be nested one level
# (config/boot/plymouth). Rather than keep a list of which prefixes are
# grouping directories -- a list that would rot the first time one was
# added -- this asks the filesystem which prefix actually carries the
# install.sh, longest match losing to shortest so a nested module wins over
# its group.
_module_owning() {
    local root rest first second
    root="$(dotfiles_root)"
    rest="${1#config/}"
    first="${rest%%/*}"

    [ -f "$root/config/$first/install.sh" ] && { printf '%s' "$first"; return 0; }

    rest="${rest#*/}"
    second="${rest%%/*}"
    if [ -n "$second" ] && [ -f "$root/config/$first/$second/install.sh" ]; then
        printf '%s/%s' "$first" "$second"
        return 0
    fi

    # Nothing owns it: a file sitting directly in a grouping directory
    # (config/boot/README.md), or the remains of a deleted module. Empty,
    # so path_target can answer 'none' rather than name a module that does
    # not exist and would be handed to a runner that cannot run it.
    printf ''
}

path_target() {
    case "$1" in
        scripts/lib/hardware.sh|scripts/install-hardware.sh|scripts/hardware-detect.sh)
                                       printf 'phase:hardware' ;;
        setup_fedora.sh)               printf 'phase:system' ;;
        config/*/*)                    local owner; owner="$(_module_owning "$1")"
                                       if [ -n "$owner" ]; then printf 'module:%s' "$owner"
                                       else printf 'none'; fi ;;
        config/*)                      printf 'none' ;;           # a stray file directly under config/
        wallpapers/*)                  printf 'module:hyprland' ;;  # consumed by prisme / set_wallpapers.sh
        bin/*|scripts/lib/*.sh|install|install_all.sh)
                                       printf 'meta:manager' ;;
        scripts/*)                     printf 'meta:manager' ;;
        *.md|*.jpg|*.png|.gitignore|.gitattributes|LICENSE)
                                       printf 'none' ;;
        *)                             printf 'unmapped' ;;
    esac
}
