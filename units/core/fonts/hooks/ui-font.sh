#!/usr/bin/env bash
# MiSans Latin as the UI font for GTK (dconf) and Qt/KDE.
. "$(dirname "$(readlink -f "$0")")/../../../lib/hook.sh"

UI_FONT="MiSans Latin"
UI_FONT_SIZE=11

if have gsettings; then
    gsettings set org.gnome.desktop.interface font-name "$UI_FONT  $UI_FONT_SIZE"
    gsettings set org.gnome.desktop.interface document-font-name "$UI_FONT  $UI_FONT_SIZE"
fi

# A GTK settings.ini the user wrote themselves gets the font too. Ours (a
# link into the repo) leaves it out on purpose: dconf above carries it.
for ini in "$HOME/.config/gtk-3.0/settings.ini" "$HOME/.config/gtk-4.0/settings.ini"; do
    [ -f "$ini" ] && [ ! -L "$ini" ] || continue
    if grep -q '^gtk-font-name=' "$ini"; then
        sed -i "s/^gtk-font-name=.*/gtk-font-name=$UI_FONT,  $UI_FONT_SIZE/" "$ini"
    else
        sed -i "/^\[Settings\]/a gtk-font-name=$UI_FONT,  $UI_FONT_SIZE" "$ini"
    fi
done

if have kwriteconfig6; then
    k() { kwriteconfig6 --file kdeglobals --group "$1" --key "$2" "$UI_FONT,$3,-1,5,400,0,0,0,0,0,0,0,0,0,0,1"; }
    k General font "$UI_FONT_SIZE"
    k General menuFont 10
    k General toolBarFont 9
    k General smallestReadableFont 8
    k WM activeFont 10
fi
ok "UI font: $UI_FONT"
