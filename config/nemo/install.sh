#!/usr/bin/env bash
set -euo pipefail

BOLD="\e[1m"
GREEN="\e[32m"
BLUE="\e[34m"
RESET="\e[0m"

info()    { echo -e "${BLUE}[INFO]${RESET}  $*"; }
ok()      { echo -e "${GREEN}[ OK ]${RESET}  $*"; }
section() { echo -e "\n${BOLD}── $* ──${RESET}\n"; }

section "Nemo Global Installation & Integration"

# 1. Install packages
info "Installing Nemo and File-Roller..."
sudo dnf install -y nemo nemo-fileroller xdg-desktop-portal-gtk

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

ok "Nemo is now fully integrated into the system."
