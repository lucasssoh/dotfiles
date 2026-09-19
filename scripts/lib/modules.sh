#!/usr/bin/env bash
# modules.sh — the module registry, and the check that keeps it honest.
#
# This replaces the hand-maintained MODULES=() array that lived in
# install_all.sh. The array itself was fine; what was missing was anything
# enforcing that it matched the filesystem. The repo has already paid for
# that absence once: fuzzel, fastfetch, firefox and mpv each had a working
# config/<name>/install.sh that NOTHING ever called, and the gap was
# invisible on a machine where they had been installed by hand. On a
# genuinely fresh install it meant no application launcher at all (fuzzel IS
# Super+Space, see hypr/keybinds.lua) and an empty workspace dashboard
# (fastfetch, see scripts/dashboard-fastfetch.sh).
#
# registry_validate() turns that class of drift from "invisible until a fresh
# machine boots wrong" into "every command fails immediately, naming the
# module". It costs a few milliseconds, so it runs on every invocation.

[ -n "${_MODULES_SH_LOADED:-}" ] && return 0
_MODULES_SH_LOADED=1

_modules_lib_dir="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
# shellcheck source=./changes.sh
. "$_modules_lib_dir/changes.sh"   # for dotfiles_root()

# ---------------------------------------------------------------------------
# The order IS the contract. Read it top to bottom; the constraints below are
# checked against it, they do not reorder it.
#
# ccnote/ccslide right after bash: .zshrc sources ~/.config/ccnote/ccnote.zsh
# and ~/.config/ccslide/ccslide.zsh, and those two paths only exist once their
# own module has run.
#
# brave sits next to firefox: it was referenced all over this repo --
# .bash_aliases' refresh-brave, the HDR tonemap window rule, veille.json's
# browser list, ActiveWindow.qml's title map -- while having no module at all,
# so a fresh machine got every piece of Brave integration except Brave.
#
# liseuse after fuzzel: the picker IS fuzzel (SUPER+F, see config/liseuse/
# liseuse), so installing it first would leave a reading library with no way
# to open it on a fresh machine.
#
# boot/plymouth sits with the desktop modules and carries no constraint of
# its own: it is the only module whose output is seen before any of this is
# running, and nothing it touches is shared with the rest. It is listed
# here rather than as an opt-in because a fresh machine without it boots
# to a black screen, which on an OLED panel is indistinguishable from a
# machine that failed to start.
#
# Module names may carry ONE level of nesting, as config/boot/ uses: the
# two things that own the screen before the desktop exists (the splash and
# the greeter) are one subject, and burying that in a flat list next to
# `mpv` lost it. A grouping directory has no install.sh of its own.
#
# hyprland last: the desktop assembles everything above it.
# ---------------------------------------------------------------------------
MODULE_ORDER=(
    fonts bash ccpkg ccnote ccslide tmux wezterm nvim wireplumber
    mangohud nemo fuzzel fastfetch firefox brave mpv liseuse
    boot/plymouth hyprland
)

# Opt-in modules: real modules, deliberately never run by default. They must
# be named explicitly.
declare -A MODULE_OPTIN=(
    [boot/login]="rewrites system login (greetd + tuigreet) and prompts interactively, which would block an otherwise unattended run"
    # This machine runs Hyprland; KDE is not wanted (asked for: "pas besoin de
    # kde"). Kept in the repo rather than deleted, but never run by default.
    #
    # It is also broken upstream as of 2026-09-16: the Reversal icon theme it
    # clones, github.com/vinceliuice/reversal-icon-theme, returns 404 -- the
    # repo was deleted, not renamed (the author still publishes a dozen other
    # icon themes, none called Reversal). GitHub answers 401 for a missing
    # repo so as not to reveal its absence, which makes `git clone` prompt for
    # a username and fail hard in any unattended run. Whoever re-enables this
    # module has to pick a replacement theme first.
    [kde]="not used on this machine, and its Reversal icon theme upstream is a 404"
)

# Hard ordering constraints, validated against MODULE_ORDER on every run.
# "@last" means "must sit in the trailing block", which is how hyprland and
# kde were expressed before: as two copy-pasted blocks after the loop.
declare -A MODULE_AFTER=(
    [ccpkg]="bash"     # the manager is only useful once ~/.local/bin is on PATH
    [ccnote]="bash"
    [ccslide]="bash"
    [liseuse]="fuzzel"
    [hyprland]="@last"
)

# How many entries form the trailing "@last" block. One, since kde became
# opt-in: hyprland alone closes the run.
MODULE_LAST_BLOCK=1

_mod_err() { echo -e "\e[31m[ ERR]\e[0m  $*" >&2; }

_mod_index_of() {
    local want="$1" i
    for i in "${!MODULE_ORDER[@]}"; do
        [ "${MODULE_ORDER[$i]}" = "$want" ] && { printf '%s' "$i"; return 0; }
    done
    return 1
}

_mod_registered() {
    local want="$1" m
    for m in "${MODULE_ORDER[@]}"; do [ "$m" = "$want" ] && return 0; done
    [ -n "${MODULE_OPTIN[$want]:-}" ] && return 0
    return 1
}

# registry_validate — returns 0 when the registry and the filesystem agree.
# Prints one line per problem; never fixes anything by itself, because every
# possible automatic fix (guessing an order, silently appending) would be a
# guess about ordering constraints that only a human knows.
registry_validate() {
    local root errs=0 m dir idx dep didx last_start
    root="$(dotfiles_root)"

    # 1. Everything registered must exist on disk.
    for m in "${MODULE_ORDER[@]}" "${!MODULE_OPTIN[@]}"; do
        [ -f "$root/config/$m/install.sh" ] || {
            _mod_err "registry: '$m' is registered but config/$m/install.sh does not exist"
            errs=1
        }
    done

    # 2. Everything on disk must be registered. THIS is the check that matters
    #    -- it is the one whose absence shipped a machine with no launcher.
    # Both depths, because a module may be nested one level (config/boot/*).
    # A directory with no install.sh is not a module; if it also holds no
    # nested one it is a stray, which case 2b below catches.
    for dir in "$root"/config/*/ "$root"/config/*/*/; do
        [ -d "$dir" ] || continue
        m="${dir#"$root"/config/}"; m="${m%/}"
        [ -f "$dir/install.sh" ] || continue
        _mod_registered "$m" || {
            _mod_err "registry: config/$m/install.sh exists but is in no list — add '$m' to MODULE_ORDER (or MODULE_OPTIN) in scripts/lib/modules.sh"
            errs=1
        }
    done

    # 2b. A directory directly under config/ that is neither a module nor a
    #     grouping directory is a stray: nothing would ever run it, which is
    #     the same class of silent gap as case 2, one level up.
    for dir in "$root"/config/*/; do
        [ -f "$dir/install.sh" ] && continue
        compgen -G "$dir*/install.sh" >/dev/null && continue
        _mod_err "registry: config/$(basename "$dir")/ has no install.sh and groups no module — nothing would ever run it"
        errs=1
    done

    # 3. No duplicates: a module listed twice would be installed twice, and
    #    would make the "comes after" arithmetic below ambiguous.
    local seen_dup
    seen_dup="$(printf '%s\n' "${MODULE_ORDER[@]}" | LC_ALL=C sort | uniq -d)"
    [ -n "$seen_dup" ] && {
        _mod_err "registry: duplicate entries in MODULE_ORDER: $(echo "$seen_dup" | tr '\n' ' ')"
        errs=1
    }

    # 4. Ordering constraints hold.
    last_start=$(( ${#MODULE_ORDER[@]} - MODULE_LAST_BLOCK ))
    for m in "${!MODULE_AFTER[@]}"; do
        idx="$(_mod_index_of "$m")" || {
            _mod_err "registry: MODULE_AFTER mentions '$m', which is not in MODULE_ORDER"
            errs=1; continue
        }
        for dep in ${MODULE_AFTER[$m]}; do
            if [ "$dep" = "@last" ]; then
                [ "$idx" -ge "$last_start" ] || {
                    _mod_err "registry: '$m' must sit in the trailing block (last $MODULE_LAST_BLOCK entries) of MODULE_ORDER"
                    errs=1
                }
                continue
            fi
            didx="$(_mod_index_of "$dep")" || {
                _mod_err "registry: '$m' is declared after '$dep', which is not in MODULE_ORDER"
                errs=1; continue
            }
            [ "$didx" -lt "$idx" ] || {
                _mod_err "registry: '$m' must come after '$dep' in MODULE_ORDER"
                errs=1
            }
        done
    done

    return "$errs"
}

# module_script <name> -> absolute path, or empty + rc 1
module_script() {
    local p; p="$(dotfiles_root)/config/$1/install.sh"
    [ -f "$p" ] || return 1
    printf '%s' "$p"
}
