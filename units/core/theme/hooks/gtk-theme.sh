#!/usr/bin/env bash
# GTK3 Adwaita-dark and Adwaita-light generated in the shell's palette; gtk-theme follows color-scheme; the Coucou icon theme.
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

# Icons: Coucou is Adwaita with the folders in the shell theme's colour,
# which shell-theme.py sync writes (Adwaita's own blue in the glass look).
# Written before it is chosen, so the name never points at nothing.
if [ -x "$HOME/.config/hypr/scripts/shell-theme.py" ]; then
    "$HOME/.config/hypr/scripts/shell-theme.py" sync >/dev/null || true
fi
if have gsettings && [ -f "${XDG_DATA_HOME:-$HOME/.local/share}/icons/Coucou/index.theme" ]; then
    # Only replace the default, never an icon theme the user chose.
    [ "$(gsettings get org.gnome.desktop.interface icon-theme)" = "'Adwaita'" ] \
        && gsettings set org.gnome.desktop.interface icon-theme Coucou
    ok "Icons: Coucou (Adwaita, folders in the theme's colour)"
fi

# The GTK portal caches the theme; running GTK apps pick it up on restart.
systemctl --user try-restart xdg-desktop-portal-gtk.service 2>/dev/null || true
