#!/usr/bin/env bash
# Nemo as the file manager: directory handler, FileManager1 D-Bus name, preferences.
. "$(dirname "$(readlink -f "$0")")/../../../lib/hook.sh"

mime="$HOME/.config/mimeapps.list"
[ -f "$mime" ] && sed -i '/inode\/directory/d' "$mime"
xdg-mime default nemo.desktop inode/directory

services="$HOME/.local/share/dbus-1/services"
mkdir -p "$services"
cat > "$services/org.freedesktop.FileManager1.service" <<EOF
[D-BUS Service]
Name=org.freedesktop.FileManager1
Exec=/usr/bin/nemo --no-default-window
EOF

if have gsettings; then
    # Only replace Nemo's own defaults, never a value the user chose.
    [ "$(gsettings get org.nemo.window-state sidebar-width)" = "170" ] \
        && gsettings set org.nemo.window-state sidebar-width 210
    [ "$(gsettings get org.nemo.preferences thumbnail-limit)" = "uint64 1048576" ] \
        && gsettings set org.nemo.preferences thumbnail-limit 33554432
fi
ok "Nemo is the file manager"
