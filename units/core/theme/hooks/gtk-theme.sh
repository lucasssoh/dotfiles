#!/usr/bin/env bash
# GTK3 Adwaita-dark and Adwaita-light generated in the shell's palette; gtk-theme follows color-scheme.
. "$(dirname "$(readlink -f "$0")")/../../../lib/hook.sh"

python3 "$REPO/config/nemo/theme/build-themes.py" >/dev/null
ok "Adwaita-dark and Adwaita-light built in ~/.local/share/themes, with their Coucou twins"

if have gsettings; then
    scheme="$(gsettings get org.gnome.desktop.interface color-scheme)"
    if [ "$scheme" = "'default'" ]; then
        gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark'
        scheme="'prefer-dark'"
    fi
    current="$(gsettings get org.gnome.desktop.interface gtk-theme)"
    case "$current" in
        # Plain Adwaita is the previous light name: moved to Adwaita-light.
        # Coucou-dark and Coucou-light are the same themes under a second
        # name, which shell-theme.py sync moves to so GTK3 apps restyle.
        "'Adwaita'"|"'Adwaita-light'"|"'Adwaita-dark'"|"'Coucou-light'"|"'Coucou-dark'")
            want=Adwaita-light
            [ "$scheme" = "'prefer-dark'" ] && want=Adwaita-dark
            case "$current" in
                "'$want'"|"'${want/Adwaita/Coucou}'") ;;
                *) gsettings set org.gnome.desktop.interface gtk-theme "$want" ;;
            esac
            ;;
    esac
fi

# The GTK portal caches the theme; running GTK apps pick it up on restart.
systemctl --user try-restart xdg-desktop-portal-gtk.service 2>/dev/null || true
