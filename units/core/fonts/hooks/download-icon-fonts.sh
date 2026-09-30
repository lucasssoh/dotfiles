#!/usr/bin/env bash
# Icon and terminal fonts the bar and WezTerm address by name or codepoint.
. "$(dirname "$(readlink -f "$0")")/../../../lib/hook.sh"

FONT_DIR="$HOME/.local/share/fonts"
mkdir -p "$FONT_DIR"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
added=0
# Pinned, all three: the bar addresses these glyphs by codepoint, and a new
# release may move them.
PHOSPHOR_VERSION="2.1.2"
LUCIDE_VERSION="1.48.0"

if ! fc-list | grep -i "GoogleSansCode Nerd Font Mono" >/dev/null; then
    info "downloading GoogleSansCode Nerd Font Mono"
    mkdir -p "$FONT_DIR/GoogleSansCode"
    curl -fsSL "https://github.com/E-Vertin/GoogleSansCode-NerdFont/releases/download/v7.000/GoogleSansCode-NFM-v7.000.tar.xz" -o "$tmp/gsc.tar.xz"
    tar -xf "$tmp/gsc.tar.xz" -C "$FONT_DIR/GoogleSansCode/"
    added=1
fi

if ! fc-list | grep -i "Phosphor" >/dev/null; then
    v="$PHOSPHOR_VERSION"
    info "downloading Phosphor Icons $v"
    curl -fsSL "https://registry.npmjs.org/@phosphor-icons/web/-/web-$v.tgz" -o "$tmp/phosphor.tgz"
    tar -xzf "$tmp/phosphor.tgz" -C "$tmp"
    for weight in thin light regular bold fill duotone; do
        find "$tmp/package/src/$weight" -maxdepth 1 -name '*.ttf' -exec cp {} "$FONT_DIR/" \;
    done
    added=1
fi

if ! fc-list | grep -i "lucide" >/dev/null; then
    v="$LUCIDE_VERSION"
    info "downloading Lucide Icons $v"
    curl -fsSL "https://registry.npmjs.org/lucide-static/-/lucide-static-$v.tgz" -o "$tmp/lucide.tgz"
    tar -xzf "$tmp/lucide.tgz" -C "$tmp" package/font/lucide.ttf
    cp "$tmp/package/font/lucide.ttf" "$FONT_DIR/"
    added=1
fi

MINGCUTE_VERSION="2.9.72"
if ! fc-list | grep -i "MingCute" >/dev/null; then
    info "downloading MingCute Icons $MINGCUTE_VERSION"
    curl -fsSL "https://registry.npmjs.org/mingcute_icon/-/mingcute_icon-$MINGCUTE_VERSION.tgz" -o "$tmp/mingcute.tgz"
    tar -xzf "$tmp/mingcute.tgz" -C "$tmp" package/font/MingCute.ttf
    cp "$tmp/package/font/MingCute.ttf" "$FONT_DIR/"
    added=1
fi

[ "$added" = 1 ] && fc-cache -f "$FONT_DIR"
ok "icon fonts in place"
