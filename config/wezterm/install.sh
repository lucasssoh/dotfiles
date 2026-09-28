#!/usr/bin/env bash
set -Eeuo pipefail

# The single safe_link (scripts/lib/link.sh). It replaces the copy that used
# to live here: that one removed and re-created the link on every run, even
# when it was already correct. This one returns early, and records what it
# did so `cc-pkg-mng verify` can check it later.
. "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../../scripts/lib/link.sh"

# Package helper: queries before it installs, so an already-provisioned
# machine performs zero package-manager calls and never prompts for sudo.
. "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../../scripts/lib/pkg.sh"

# The variant choice lives in the state file: `cc-pkg-mng wezterm <variant>`
# writes it, this module reads it.
. "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../../scripts/lib/state.sh"

GREEN="\e[32m"
YELLOW="\e[33m"
RESET="\e[0m"

info() { echo -e "[INFO]  $*"; }
ok()   { echo -e "${GREEN}[ OK ]${RESET}  $*"; }
warn() { echo -e "${YELLOW}[WARN]${RESET}  $*" >&2; }

DOTFILES_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../.." && pwd)"

# 1. Install WezTerm
# The third-party repo is only touched when wezterm is actually absent:
# `dnf copr enable` on an already-enabled copr is harmless but still wakes
# dnf and needs root, which is exactly what this module must stop doing on
# every run.
#
# Installed in both variants: the smear build only replaces the two binaries,
# and still relies on the package for the desktop entry, the terminfo and the
# shell integration.
if ! pkg_installed wezterm; then
    case "$(pkg_mgr)" in
        dnf) sudo_maybe dnf copr enable wezfurlong/wezterm-nightly -y ;;
        apt)
            curl -fsSL https://apt.fury.io/wez/gpg.key | sudo_maybe gpg --yes --dearmor -o /usr/share/keyrings/wezterm-fury.gpg
            echo 'deb [signed-by=/usr/share/keyrings/wezterm-fury.gpg] https://apt.fury.io/wez/ * *' | sudo_maybe tee /etc/apt/sources.list.d/wezterm.list
            sudo_maybe apt-get update
            ;;
    esac
fi
pkg_ensure wezterm

# 2. Variant: the packaged build, or one compiled with a native cursor smear.
#
# The smear is wezterm PR #7737, not merged upstream yet, pinned to the commit
# below, plus smear/pane-handoff.patch so it also travels across pane and tab
# switches. Bumping SMEAR_BASE or editing the patch changes this module's
# fingerprint, so the next `update` rebuilds.
#
# The binaries go to /usr/local/bin, not ~/.local/bin: Hyprland and quickshell
# launch `wezterm` with the session PATH, which has /usr/local/bin ahead of
# /usr/bin but no ~/.local/bin at all.
SMEAR_REPO="https://github.com/wezterm/wezterm.git"
SMEAR_PR=7737
SMEAR_BASE=114a305daaaf781044694e92127928f83c627770
SMEAR_PATCH="$DOTFILES_DIR/config/wezterm/smear/pane-handoff.patch"
SMEAR_SRC="${XDG_CACHE_HOME:-$HOME/.cache}/dotfiles/wezterm-smear"
SMEAR_BINS=(wezterm wezterm-gui)
SMEAR_DEST=/usr/local/bin

state_load
variant="$(state_get wezterm.variant stable)"

# sha256 of each binary as this module installed it. Only a binary that still
# matches is ever removed: whatever else sits in /usr/local/bin under that name
# was put there by someone else.
installed_matches() {
    local b
    for b in "${SMEAR_BINS[@]}"; do
        [ -f "$SMEAR_DEST/$b" ] || return 1
        [ "$(sha256sum "$SMEAR_DEST/$b" | cut -d' ' -f1)" = "$(state_get "wezterm.smear.sha.$b")" ] || return 1
    done
}

# A deferred root step (user scope) leaves the machine on the wrong variant, so
# the module exits non-zero: `update` then retries it instead of recording it
# as applied, and `update --system` finishes the job.
deferred=0
root_step() {
    sudo_maybe "$@"
    [ "$CCPKG_ALLOW_ROOT" = 1 ] || deferred=1
}

# Every step ends in `|| return 1`: this runs as an `elif` condition, where
# `set -e` is off, and a failed `git apply` must not go on to build an
# unpatched tree.
build_smear() {
    command -v cargo >/dev/null 2>&1 || { warn "cargo not found — install a Rust toolchain first."; return 1; }

    # The X11/Wayland/EGL headers the build links against, beyond a Rust
    # toolchain. Names from wezterm's own get-deps, for the distros it lists.
    local deps=(
        "$(pkg_pick openssl-devel openssl libssl-dev)"
        "$(pkg_pick fontconfig-devel fontconfig libfontconfig1-dev)"
        "$(pkg_pick libxcb-devel libxcb libxcb1-dev)"
        "$(pkg_pick libxkbcommon-x11-devel libxkbcommon-x11 libxkbcommon-x11-dev)"
        "$(pkg_pick wayland-devel wayland libwayland-dev)"
        "$(pkg_pick mesa-libEGL-devel mesa libegl1-mesa-dev)"
        "$(pkg_pick xcb-util-devel xcb-util libxcb-util-dev)"
        "$(pkg_pick xcb-util-image-devel xcb-util-image libxcb-image0-dev)"
        "$(pkg_pick xcb-util-keysyms-devel xcb-util-keysyms libxcb-keysyms1-dev)"
        "$(pkg_pick xcb-util-wm-devel xcb-util-wm libxcb-ewmh-dev)"
        "$(pkg_pick perl-FindBin perl perl)"
    )
    pkg_ensure "${deps[@]}"
    # pkg_ensure returns 0 on a deferral; building without the headers would
    # only fail ten minutes later.
    local p
    for p in "${deps[@]}"; do
        pkg_installed "$p" || { warn "build dependencies missing — the smear build needs --system."; deferred=1; return 1; }
    done

    if [ ! -d "$SMEAR_SRC/.git" ]; then
        info "cloning wezterm into $SMEAR_SRC…"
        mkdir -p "$(dirname "$SMEAR_SRC")"
        git clone --quiet --filter=blob:none "$SMEAR_REPO" "$SMEAR_SRC" || return 1
    fi
    if ! git -C "$SMEAR_SRC" cat-file -e "$SMEAR_BASE^{commit}" 2>/dev/null; then
        info "fetching PR #$SMEAR_PR…"
        git -C "$SMEAR_SRC" fetch --quiet origin "pull/$SMEAR_PR/head" || return 1
    fi

    # Back to the pinned tree, then the patch on top. `apply`, not `am`: no
    # commit is made, so no git identity is needed on a fresh machine.
    git -C "$SMEAR_SRC" checkout --quiet --force --detach "$SMEAR_BASE" || return 1
    git -C "$SMEAR_SRC" reset --quiet --hard || return 1
    git -C "$SMEAR_SRC" apply "$SMEAR_PATCH" || return 1
    git -C "$SMEAR_SRC" submodule --quiet update --init --recursive || return 1

    info "building wezterm with cursor smear (~5 min the first time)…"
    ( cd "$SMEAR_SRC" && cargo build --release -p wezterm-gui -p wezterm ) || return 1
}

case "$variant" in
    smear)
        key="$SMEAR_BASE|$(sha256sum "$SMEAR_PATCH" | cut -d' ' -f1)|$(cargo --version 2>/dev/null)"
        if [ "$(state_get wezterm.smear.key)" = "$key" ] && installed_matches; then
            info "wezterm (smear): up to date."
        elif build_smear; then
            root_step install -m755 "${SMEAR_BINS[@]/#/$SMEAR_SRC/target/release/}" "$SMEAR_DEST/"
            if [ "$deferred" = 0 ]; then
                for b in "${SMEAR_BINS[@]}"; do
                    state_set "wezterm.smear.sha.$b" "$(sha256sum "$SMEAR_DEST/$b" | cut -d' ' -f1)"
                done
                state_set wezterm.smear.key "$key"
                state_save
                ok "wezterm (smear) installed to $SMEAR_DEST."
            fi
        else
            # The binary already installed, if any, is left alone: a broken
            # build must not also take away the terminal you are typing in.
            if [ "$deferred" = 0 ]; then
                warn "wezterm (smear): build failed — the installed wezterm is left in place."
                exit 1
            fi
        fi
        ;;
    stable)
        if installed_matches; then
            info "removing the smear build from $SMEAR_DEST…"
            root_step rm -f "${SMEAR_BINS[@]/#/$SMEAR_DEST/}"
            if [ "$deferred" = 0 ]; then
                for b in "${SMEAR_BINS[@]}"; do state_unset "wezterm.smear.sha.$b"; done
                state_unset wezterm.smear.key
                state_save
            fi
        elif [ -e "$SMEAR_DEST/wezterm" ]; then
            warn "$SMEAR_DEST/wezterm was not installed by this module — left in place, it still shadows the package."
        fi
        ;;
    *)
        warn "unknown wezterm.variant '$variant' — expected stable or smear."
        exit 1
        ;;
esac
[ "$deferred" = 0 ] || { warn "wezterm ($variant): root steps deferred — run cc-pkg-mng update --system."; exit 1; }

# 3. Symlinks
mkdir -p ~/.config/wezterm

# Link the config
safe_link "$DOTFILES_DIR/config/wezterm/wezterm.lua" ~/.wezterm.lua
safe_link "$DOTFILES_DIR/config/wezterm/wezterm.lua" ~/.config/wezterm/wezterm.lua

ok "WezTerm configured ($variant)."
