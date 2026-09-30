#!/usr/bin/env bash
# WezTerm variant: stable (package) or smear (PR #7737 built into /usr/local/bin).
. "$(dirname "$(readlink -f "$0")")/../../../lib/hook.sh"

variant="${CCPKG_ANSWER_VARIANT:-stable}"
REPO_URL="https://github.com/wezterm/wezterm.git"
PR=7737
BASE=114a305daaaf781044694e92127928f83c627770
PATCH="$REPO/config/wezterm/smear/pane-handoff.patch"
SRC="${XDG_CACHE_HOME:-$HOME/.cache}/dotfiles/wezterm-smear"
BINS=(wezterm wezterm-gui)
DEST=/usr/local/bin
STAMP="$HOOK_STATE/smear.env"   # key and sha256 of what this hook installed

sha() { sha256sum "$1" | cut -d' ' -f1; }
ours() {   # are the binaries in $DEST the ones this hook installed?
    [ -f "$STAMP" ] || return 1
    local b
    for b in "${BINS[@]}"; do
        [ -f "$DEST/$b" ] && grep -qx "$b=$(sha "$DEST/$b")" "$STAMP" || return 1
    done
}

case "$variant" in
stable)
    if ours; then
        as_root rm -f "${BINS[@]/#/$DEST/}"
        rm -f "$STAMP"
        ok "smear build removed, the packaged wezterm is back"
    elif [ -e "$DEST/wezterm" ]; then
        warn "$DEST/wezterm was not installed by coucou-shell; left in place (it shadows the package)"
    else
        ok "packaged wezterm"
    fi
    ;;
smear)
    key="$BASE|$(sha "$PATCH")|$(cargo --version 2>/dev/null)"
    if ours && grep -qx "key=$key" "$STAMP"; then
        ok "smear build up to date"
        exit 0
    fi
    deps=(openssl-devel fontconfig-devel libxcb-devel libxkbcommon-x11-devel wayland-devel
          mesa-libEGL-devel xcb-util-devel xcb-util-image-devel xcb-util-keysyms-devel
          xcb-util-wm-devel perl-FindBin rust cargo)
    missing=()
    for p in "${deps[@]}"; do rpm -q --whatprovides "$p" >/dev/null 2>&1 || missing+=("$p"); done
    [ "${#missing[@]}" -eq 0 ] || as_root dnf install -y "${missing[@]}"

    if [ ! -d "$SRC/.git" ]; then
        mkdir -p "$(dirname "$SRC")"
        git clone --quiet --filter=blob:none "$REPO_URL" "$SRC"
    fi
    git -C "$SRC" cat-file -e "$BASE^{commit}" 2>/dev/null || git -C "$SRC" fetch --quiet origin "pull/$PR/head"
    git -C "$SRC" checkout --quiet --force --detach "$BASE"
    git -C "$SRC" reset --quiet --hard
    git -C "$SRC" apply "$PATCH"
    git -C "$SRC" submodule --quiet update --init --recursive
    info "building wezterm with cursor smear (about 5 minutes the first time)"
    (cd "$SRC" && cargo build --release -p wezterm-gui -p wezterm)

    as_root install -m755 "${BINS[@]/#/$SRC/target/release/}" "$DEST/"
    { echo "key=$key"; for b in "${BINS[@]}"; do echo "$b=$(sha "$DEST/$b")"; done; } > "$STAMP"
    ok "smear build installed in $DEST"
    ;;
*)
    warn "unknown variant '$variant' (expected stable or smear)"
    exit 1
    ;;
esac
