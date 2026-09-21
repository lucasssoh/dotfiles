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
ln -sf "$SCRIPT_DIR/hyprland-portals.conf" "$XDG_CONF_DIR/hyprland-portals.conf"

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

# Mask Dolphin D-Bus activator if present and link it to Nemo's service definition
cat << EOF > "$DBUS_SERVICES_DIR/org.freedesktop.FileManager1.service"
[D-BUS Service]
Name=org.freedesktop.FileManager1
Exec=/usr/bin/nemo --no-desktop --gapplication-service
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
# Both files land in ~/.config/gtk-3.0, so they reach every GTK3 app on the
# machine, not only Nemo. That is intentional and worth naming: the other
# GTK3 surface on this desktop is xdg-desktop-portal-gtk's file chooser,
# installed by this very module a few lines up, and a file chooser that did
# not match the file manager that opens next to it would be the odd one out.
# Nothing else here is GTK3 -- the bar is Quickshell, fuzzel is native,
# the browsers draw their own chrome.
info "Theming GTK3 (Nemo + the GTK file chooser portal)..."
mkdir -p "$HOME/.config/gtk-3.0"
safe_link "$SCRIPT_DIR/gtk-3.0/settings.ini" "$HOME/.config/gtk-3.0/settings.ini"
safe_link "$SCRIPT_DIR/gtk-3.0/gtk.css"      "$HOME/.config/gtk-3.0/gtk.css"

# The dconf half, and the actual reason Nemo came up white while the rest of
# the desktop was dark: the session carried gtk-theme='Adwaita-dark', and no
# such GTK3 theme exists. /usr/share/themes has no Adwaita at all on Fedora
# (GTK3 ships it compiled into libgtk-3 as a gresource), and that resource
# holds ONE theme named "Adwaita" whose dark variant is selected by the
# boolean gtk-application-prefer-dark-theme, not a second theme named
# "Adwaita-dark". The name resolved to nothing and GTK3 fell back to light.
#
# This has to be fixed HERE and not only in settings.ini: with
# xdg-desktop-portal-gtk running, GTK3 reads org.gnome.desktop.interface
# through the portal, and that value outranks settings.ini. Left alone, the
# stale name would keep winning and the theme below it would never show.
#
# 'Adwaita-dark' is only ever wrong, so it is rewritten rather than
# preserved; any other value is somebody's deliberate choice and is left be.
if command -v gsettings &> /dev/null; then
    CUR_GTK_THEME="$(gsettings get org.gnome.desktop.interface gtk-theme 2>/dev/null || echo "")"
    if [ "$CUR_GTK_THEME" = "'Adwaita-dark'" ]; then
        info "Rewriting gtk-theme 'Adwaita-dark' (not a GTK3 theme) -> 'Adwaita' + prefer-dark..."
        gsettings set org.gnome.desktop.interface gtk-theme 'Adwaita'
    fi
    # GTK4/libadwaita reads this one; GTK3 does not, hence the pair.
    gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark' || true
fi

ok "Nemo is now fully integrated into the system."
