#!/usr/bin/env bash
# GTK3 Adwaita-dark generated in the bar's palette; gtk-theme follows color-scheme.
. "$(dirname "$(readlink -f "$0")")/../../../lib/hook.sh"

python3 "$REPO/config/nemo/theme/build-adwaita-dark.py" >/dev/null
ok "Adwaita-dark built in ~/.local/share/themes"

if have gsettings; then
    scheme="$(gsettings get org.gnome.desktop.interface color-scheme)"
    if [ "$scheme" = "'default'" ]; then
        gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark'
        scheme="'prefer-dark'"
    fi
    current="$(gsettings get org.gnome.desktop.interface gtk-theme)"
    case "$current" in
        "'Adwaita'"|"'Adwaita-dark'")
            want=Adwaita
            [ "$scheme" = "'prefer-dark'" ] && want=Adwaita-dark
            [ "$current" = "'$want'" ] || gsettings set org.gnome.desktop.interface gtk-theme "$want"
            ;;
    esac
fi

# The GTK portal caches the theme; running GTK apps pick it up on restart.
systemctl --user try-restart xdg-desktop-portal-gtk.service 2>/dev/null || true
