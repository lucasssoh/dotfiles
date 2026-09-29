#!/usr/bin/env bash
set -Eeuo pipefail

# Package helper: queries before it installs, so an already-provisioned
# machine performs zero package-manager calls and never prompts for sudo.
. "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../../scripts/lib/pkg.sh"

# The single safe_link (scripts/lib/link.sh): returns early when the link is
# already correct, and records what it did so `cc-pkg-mng verify` can check it.
. "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../../scripts/lib/link.sh"

BOLD="\e[1m"
GREEN="\e[32m"
BLUE="\e[34m"
RESET="\e[0m"

info()    { echo -e "${BLUE}[INFO]${RESET}  $*"; }
ok()      { echo -e "${GREEN}[ OK ]${RESET}  $*"; }
section() { echo -e "\n${BOLD}── $* ──${RESET}\n"; }

section "Nemo Global Installation & Integration"

# 1. Install packages
pkg_ensure nemo nemo-fileroller xdg-desktop-portal-gtk

# 2. Configure XDG Desktop Portal
info "Configuring XDG Desktop Portal..."
XDG_CONF_DIR="$HOME/.config/xdg-desktop-portal"
mkdir -p "$XDG_CONF_DIR"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Symlink portal priorities configuration
safe_link "$SCRIPT_DIR/hyprland-portals.conf" "$XDG_CONF_DIR/hyprland-portals.conf"

# 3. Clean up and force MIME types
MIME_FILE="$HOME/.config/mimeapps.list"
if [ -f "$MIME_FILE" ]; then
    info "Purging old directory associations (Dolphin/Thunar) to avoid duplicates..."
    sed -i '/inode\/directory/d' "$MIME_FILE"
fi

info "Setting Nemo as the default file manager..."
xdg-mime default nemo.desktop inode/directory

# 4. Create local D-Bus service override for FileManager1 (prevents crashes from missing Dolphin)
DBUS_SERVICES_DIR="$HOME/.local/share/dbus-1/services"
info "Setting up D-Bus FileManager1 interface redirect to Nemo..."
mkdir -p "$DBUS_SERVICES_DIR"

# Mask Dolphin D-Bus activator if present and link it to Nemo's service definition.
# --no-default-window is what Nemo's own /usr/share/dbus-1/services files
# use; --gapplication-service, used here before, is not a Nemo 6.6 option
# -- activation exited on "Option inconnue" and "open folder" from another
# app failed whenever no Nemo window was already open.
cat << EOF > "$DBUS_SERVICES_DIR/org.freedesktop.FileManager1.service"
[D-BUS Service]
Name=org.freedesktop.FileManager1
Exec=/usr/bin/nemo --no-default-window
EOF

# 5. Reload and restart user services
info "Reloading systemd user daemons..."
systemctl --user daemon-reload
systemctl --user restart xdg-desktop-portal.service || true

# 6. Theme Nemo to match the bar
#
# Nemo is GTK3 (`ldd /usr/bin/nemo` -> libgtk-3.so.0), which is the whole
# reason this section is here rather than in the Qt side of the desktop:
# qt6ct, which QT_QPA_PLATFORMTHEME points at, never sees this window.
#
# Everything here reaches every GTK3 app on the machine, not only Nemo.
# That is intentional: the other GTK3 surface on this desktop is
# xdg-desktop-portal-gtk's file chooser, installed by this very module a
# few lines up, and a file chooser that did not match the file manager
# that opens next to it would be the odd one out.
#
# Three pieces, because the bar's appearance toggle (AppearanceState.qml)
# switches GTK3 by theme NAME -- "Adwaita-dark" / "Adwaita" in
# org.gnome.desktop.interface gtk-theme:
#   a. ~/.local/share/themes/Adwaita-dark, GENERATED from the Adwaita dark
#      sheet compiled into libgtk-3, recoloured to the bar's palette, plus
#      theme/overlay.css. GTK3 has no built-in theme by that name, so until
#      this exists "Adwaita-dark" silently means LIGHT Adwaita -- which is
#      what Nemo had been running on under a dark-only user stylesheet
#      (white properties page, blue tab underline, invisible disk gauges).
#      Rebuilt on every run: it is cheap and it tracks GTK updates.
#   b. ~/.config/gtk-3.0/{settings.ini,gtk.css}: the no-portal fallback and
#      colour-free geometry that reads right on both themes.
#   c. dconf, below.
info "Theming GTK3 (Nemo + the GTK file chooser portal)..."
python3 "$SCRIPT_DIR/theme/build-adwaita-dark.py" >/dev/null
# A running GTK3 process resolves its theme once, at startup, and never
# re-reads the files: the file-chooser portal, alive since login, would
# keep drawing whatever the theme was before this run (seen: a light
# path bar in Firefox's "Enregistrer sous"). try-restart: only if running.
systemctl --user try-restart xdg-desktop-portal-gtk.service 2>/dev/null || true
mkdir -p "$HOME/.config/gtk-3.0"
safe_link "$SCRIPT_DIR/gtk-3.0/settings.ini" "$HOME/.config/gtk-3.0/settings.ini"
safe_link "$SCRIPT_DIR/gtk-3.0/gtk.css"      "$HOME/.config/gtk-3.0/gtk.css"

# The dconf half. With xdg-desktop-portal-gtk running, GTK3 reads gtk-theme
# through the portal and that outranks settings.ini, so the two keys have
# to agree HERE:
#   color-scheme  read by GTK4/libadwaita and the browsers; GTK3 ignores it.
#   gtk-theme     the only one GTK3 follows.
# color-scheme is only chosen when nobody has ('default'): after that it is
# the bar toggle's to own. gtk-theme is then aligned to it -- which also
# migrates a machine set up by the previous version of this script, which
# rewrote 'Adwaita-dark' to 'Adwaita' + prefer-dark (dark only through
# settings.ini's prefer-dark flag, now 0 so the light toggle works).
# A value that is neither Adwaita name is somebody's choice and is left be.
if command -v gsettings &> /dev/null; then
    CUR_SCHEME="$(gsettings get org.gnome.desktop.interface color-scheme 2>/dev/null || echo "")"
    if [ "$CUR_SCHEME" = "'default'" ]; then
        gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark' || true
        CUR_SCHEME="'prefer-dark'"
    fi
    CUR_GTK_THEME="$(gsettings get org.gnome.desktop.interface gtk-theme 2>/dev/null || echo "")"
    case "$CUR_GTK_THEME" in
        "'Adwaita'"|"'Adwaita-dark'")
            WANT="Adwaita"
            [ "$CUR_SCHEME" = "'prefer-dark'" ] && WANT="Adwaita-dark"
            if [ "$CUR_GTK_THEME" != "'$WANT'" ]; then
                info "Aligning gtk-theme with color-scheme -> '$WANT'..."
                gsettings set org.gnome.desktop.interface gtk-theme "$WANT"
            fi
            ;;
    esac
fi

# Sidebar width. Nemo's default, 170 px, cuts "Dossier personnel" and
# "Système de fichiers" to "Dossier pe..." / "Système d..." in MiSans 11 --
# and the disk gauge is drawn under that clipped label. 210 fits both.
# Only raised from Nemo's default, never from a width somebody dragged.
if command -v gsettings &> /dev/null; then
    if [ "$(gsettings get org.nemo.window-state sidebar-width 2>/dev/null)" = "170" ]; then
        gsettings set org.nemo.window-state sidebar-width 210
    fi
fi

# 7. Thumbnails
#
# Nemo's own default for `thumbnail-limit` is 1 MiB, and it is a hard cut:
# any image over it gets the generic mimetype icon, never a thumbnail. On
# this machine that lands badly on wallpapers/ -- 13 of its 43 files are
# over 1 MiB, INCLUDING both of the only two .jpg in the folder (the
# 4096x4096 morphogenesis pair, ~1.7 MiB each). The result reads as "Nemo
# cannot thumbnail JPEG", which is what it looked like from the outside and
# is not what is happening: `GdkPixbuf.Pixbuf.get_formats()` lists jpeg AND
# jxl here, and every .jxl UNDER the limit thumbnails fine. It is a size
# cut-off wearing a format's clothes.
#
# 32 MiB clears everything in wallpapers/ with room to spare (the largest
# is 4.3 MiB) while still refusing the genuinely pathological file the
# setting exists to guard against.
#
# Only raised when it is still sitting on Nemo's default, same rule as the
# gtk-theme rewrite above: a value somebody chose is a value we leave.
if command -v gsettings &> /dev/null; then
    CUR_THUMB_LIMIT="$(gsettings get org.nemo.preferences thumbnail-limit 2>/dev/null || echo "")"
    if [ "$CUR_THUMB_LIMIT" = "uint64 1048576" ]; then
        info "Raising Nemo's 1 MiB thumbnail limit to 32 MiB..."
        gsettings set org.nemo.preferences thumbnail-limit 33554432
    fi
fi

ok "Nemo is now fully integrated into the system."
