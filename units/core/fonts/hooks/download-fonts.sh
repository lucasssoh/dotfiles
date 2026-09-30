#!/usr/bin/env bash
# Nerd Fonts and MiSans Latin into ~/.local/share/fonts, when absent.
. "$(dirname "$(readlink -f "$0")")/../../../lib/hook.sh"

FONT_DIR="$HOME/.local/share/fonts"
mkdir -p "$FONT_DIR"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
added=0

# archive name (Nerd Fonts release) -> family name it installs. Cascadia
# Code ships as "CaskaydiaCove": matched by the archive name, it was never
# found and got downloaded again on every run.
declare -A FAMILY=(
    [JetBrainsMono]="JetBrainsMono Nerd Font"
    [Iosevka]="Iosevka Nerd Font"
    [CascadiaCode]="CaskaydiaCove Nerd Font"
)
for font in JetBrainsMono Iosevka CascadiaCode; do
    if fc-list : family | grep -iF "${FAMILY[$font]}" >/dev/null; then
        info "$font already installed"
        continue
    fi
    info "downloading $font Nerd Font"
    curl -fsSL "https://github.com/ryanoasis/nerd-fonts/releases/latest/download/${font}.zip" -o "$tmp/$font.zip"
    mkdir -p "$FONT_DIR/$font"
    unzip -oq "$tmp/$font.zip" -d "$FONT_DIR/$font"
    added=1
done

# MiSans Latin: the UI font of the bar, Fuzzel, Roue and Prisme. Only the
# static TTFs are kept.
if fc-list : family | grep -i "MiSans Latin" >/dev/null; then
    info "MiSans Latin already installed"
else
    info "downloading MiSans Latin"
    curl -fsSL "https://hyperos.mi.com/font-download/MiSans_Latin.zip" -o "$tmp/misans.zip"
    mkdir -p "$FONT_DIR/MiSansLatin"
    unzip -oqj "$tmp/misans.zip" "MiSans Latin/ttf/*.ttf" -d "$FONT_DIR/MiSansLatin"
    added=1
fi

[ "$added" = 1 ] && fc-cache -f "$FONT_DIR"
ok "fonts in place"
