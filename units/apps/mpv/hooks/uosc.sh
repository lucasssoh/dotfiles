#!/usr/bin/env bash
# uosc (a modern interface for mpv) and thumbfast (thumbnails over the
# timeline), at pinned versions checked by sha256.
. "$(dirname "$(readlink -f "$0")")/../../../lib/hook.sh"

UOSC_VERSION="5.13.0"
UOSC_SHA256="4be9da3289285300fa374496c3f1bfd7bb20ac08e890d25bd5a06b28eebe4882"
THUMBFAST_COMMIT="0f711de3138c9bd6718209d819ac54022c23ded2"
THUMBFAST_SHA256="a3d08e71eae8b892f6cd39f9593ea219768e709312d176bca883841b156448bf"

mpv_dir="$HOME/.config/mpv"
mkdir -p "$mpv_dir/scripts" "$mpv_dir/fonts"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT

if [ "$(cat "$HOOK_STATE/uosc.version" 2>/dev/null)" != "$UOSC_VERSION" ]; then
    info "downloading uosc $UOSC_VERSION"
    curl -fsSL "https://github.com/tomasklaen/uosc/releases/download/$UOSC_VERSION/uosc.zip" -o "$tmp/uosc.zip"
    echo "$UOSC_SHA256  $tmp/uosc.zip" | sha256sum -c --quiet
    unzip -qo "$tmp/uosc.zip" -d "$tmp/uosc"
    rm -f "$tmp/uosc/scripts/uosc/bin/ziggy-darwin" "$tmp/uosc/scripts/uosc/bin/ziggy-windows.exe"
    rm -rf "$mpv_dir/scripts/uosc"
    cp -r "$tmp/uosc/scripts/uosc" "$mpv_dir/scripts/"
    cp "$tmp/uosc/fonts/"* "$mpv_dir/fonts/"
    echo "$UOSC_VERSION" > "$HOOK_STATE/uosc.version"
fi

if [ "$(cat "$HOOK_STATE/thumbfast.commit" 2>/dev/null)" != "$THUMBFAST_COMMIT" ]; then
    info "downloading thumbfast ${THUMBFAST_COMMIT:0:7}"
    curl -fsSL "https://raw.githubusercontent.com/po5/thumbfast/$THUMBFAST_COMMIT/thumbfast.lua" -o "$tmp/thumbfast.lua"
    echo "$THUMBFAST_SHA256  $tmp/thumbfast.lua" | sha256sum -c --quiet
    cp "$tmp/thumbfast.lua" "$mpv_dir/scripts/"
    echo "$THUMBFAST_COMMIT" > "$HOOK_STATE/thumbfast.commit"
fi
ok "uosc $UOSC_VERSION and thumbfast in ~/.config/mpv"
