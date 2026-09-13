#!/usr/bin/env bash
set -Eeuo pipefail

BOLD="\e[1m"
BLUE="\e[34m"
GREEN="\e[32m"
RESET="\e[0m"

info()    { echo -e "${BLUE}[INFO]${RESET}  $*"; }
ok()      { echo -e "${GREEN}[ OK ]${RESET}  $*"; }
section() { echo -e "\n${BOLD}── $* ──${RESET}\n"; }

FONT_DIR="$HOME/.local/share/fonts"
mkdir -p "$FONT_DIR"

# Must be initialized: read unconditionally below, and with `set -u` an
# unset read is a hard error, not just an empty string.
NEEDS_CACHE_RELOAD=false

# List of fonts to install (exact names for the GitHub URL)
# Using an array so more can be added easily
FONTS=("JetBrainsMono" "Iosevka" "CascadiaCode")

for FONT in "${FONTS[@]}"; do
    # Check whether the font is already installed (case-insensitive with -i)
    if fc-list : family | grep -iq "$FONT"; then
        info "$FONT is already installed."
    else
        info "Downloading $FONT Nerd Font..."
        # Download straight into /tmp under the font's name
        curl -L "https://github.com/ryanoasis/nerd-fonts/releases/latest/download/${FONT}.zip" -o "/tmp/${FONT}.zip"

        info "Extracting $FONT..."
        # One subfolder per font to keep ~/.local/share/fonts tidy
        mkdir -p "$FONT_DIR/$FONT"
        unzip -o "/tmp/${FONT}.zip" -d "$FONT_DIR/$FONT"

        rm "/tmp/${FONT}.zip"
        ok "$FONT installed successfully."

        # Flag that the cache needs a refresh
        NEEDS_CACHE_RELOAD=true
    fi
done

# MiSans Latin -- the UI font for the bar, Fuzzel, Roue and Prisme (see
# config/hyprland/theme/fonts.css). Not a Nerd Font, so it can't ride the
# loop above: it comes as one zip straight off Xiaomi's own font site,
# free for commercial use, and only the static TTFs are kept (the zip
# also carries otf/woff/woff2 and a variable font nothing here uses).
# Installed under its own subfolder, same as the Nerd Fonts above.
if fc-list : family | grep -iq "MiSans Latin"; then
    info "MiSans Latin is already installed."
else
    info "Downloading MiSans Latin..."
    curl -L "https://hyperos.mi.com/font-download/MiSans_Latin.zip" -o "/tmp/MiSans_Latin.zip"

    info "Extracting MiSans Latin..."
    mkdir -p "$FONT_DIR/MiSansLatin"
    # -j flattens the zip's "MiSans Latin/ttf/" nesting; only the static
    # TTFs are pulled out, which also skips the __MACOSX junk entries.
    unzip -o -j "/tmp/MiSans_Latin.zip" "MiSans Latin/ttf/*.ttf" -d "$FONT_DIR/MiSansLatin"

    rm "/tmp/MiSans_Latin.zip"
    ok "MiSans Latin installed successfully."

    NEEDS_CACHE_RELOAD=true
fi

# Only refresh the cache once at the end, if needed
if [ "$NEEDS_CACHE_RELOAD" = true ]; then
    info "Updating font cache..."
    fc-cache -fv
    ok "All fonts are ready."
else
    info "No new fonts to install."
fi

# ============================================================
# UI FONT, EVERYWHERE ELSE
# ============================================================
# Installing the file is only half of it: the desktop then has to be told
# to use it. config/hyprland/theme/fonts.css covers the four apps we
# write ourselves (bar, Fuzzel, Roue, Prisme); everything below covers
# the ones we don't.
#
# Three separate mechanisms, because no single one reaches everybody:
#   - fontconfig, for whatever asks for a generic `sans-serif` rather
#     than a named family. That is Firefox's and Brave's page text, and
#     any widget that never consults a settings key. See the long header
#     comment in 70-ui-font.conf for why that file looks the way it does.
#   - gtk-font-name, for GTK widgets. Also what draws Firefox's and
#     Brave's own chrome, since both take their UI font from GTK.
#   - kdeglobals, for Qt/KDE apps. It is also the file kde-gtk-config
#     (pulled in by config/kde/install.sh) regenerates the GTK
#     settings.ini files from whenever a Plasma session runs, so leaving
#     it on the old font would quietly undo the GTK half above.
section "UI font"

UI_FONT="MiSans Latin"
UI_FONT_SIZE=11
DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

info "Linking the fontconfig rule..."
mkdir -p "$HOME/.config/fontconfig/conf.d"
ln -sfn "$DOTFILES_DIR/config/fonts/70-ui-font.conf" \
        "$HOME/.config/fontconfig/conf.d/70-ui-font.conf"

info "Setting the GTK font..."
for GTK_INI in "$HOME/.config/gtk-3.0/settings.ini" "$HOME/.config/gtk-4.0/settings.ini"; do
    [ -f "$GTK_INI" ] || continue
    if grep -q '^gtk-font-name=' "$GTK_INI"; then
        sed -i "s/^gtk-font-name=.*/gtk-font-name=$UI_FONT,  $UI_FONT_SIZE/" "$GTK_INI"
    else
        # No [Settings] section to append under would mean a file we did
        # not write; only touch one that already looks like ours.
        sed -i "/^\[Settings\]/a gtk-font-name=$UI_FONT,  $UI_FONT_SIZE" "$GTK_INI"
    fi
done

# GTK4/libadwaita apps under a portal read this rather than settings.ini.
if command -v gsettings &> /dev/null; then
    info "Setting the GNOME interface font..."
    gsettings set org.gnome.desktop.interface font-name "$UI_FONT  $UI_FONT_SIZE"
    gsettings set org.gnome.desktop.interface document-font-name "$UI_FONT  $UI_FONT_SIZE"
fi

# Sizes differ per role here and are kept as they were; only the family
# moves. `fixed` is left alone on purpose: that one is the monospace
# slot and stays JetBrains/Iosevka.
if command -v kwriteconfig6 &> /dev/null; then
    info "Setting the Qt/KDE fonts..."
    kwriteconfig6 --file kdeglobals --group General --key font \
        "$UI_FONT,$UI_FONT_SIZE,-1,5,400,0,0,0,0,0,0,0,0,0,0,1"
    kwriteconfig6 --file kdeglobals --group General --key menuFont \
        "$UI_FONT,10,-1,5,400,0,0,0,0,0,0,0,0,0,0,1"
    kwriteconfig6 --file kdeglobals --group General --key toolBarFont \
        "$UI_FONT,9,-1,5,400,0,0,0,0,0,0,0,0,0,0,1"
    kwriteconfig6 --file kdeglobals --group General --key smallestReadableFont \
        "$UI_FONT,8,-1,5,400,0,0,0,0,0,0,0,0,0,0,1"
    kwriteconfig6 --file kdeglobals --group WM --key activeFont \
        "$UI_FONT,10,-1,5,400,0,0,0,0,0,0,0,0,0,0,1"
fi

ok "UI font set to $UI_FONT everywhere. Restart running apps to see it."
