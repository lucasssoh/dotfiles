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
    # "Open in Terminal" runs this command. Fedora 45's Cinnamon schema
    # defaults it to velocitty, which nothing installs: a terminal that
    # isn't there is replaced by xdg-terminal-exec, which follows the
    # terminal you chose, or by WezTerm where that tool isn't installed.
    term_key="org.cinnamon.desktop.default-applications.terminal"
    term="$(gsettings get "$term_key" exec 2>/dev/null | tr -d "'")"
    if [ -n "$term" ] && ! have "$term"; then
        if have xdg-terminal-exec; then
            gsettings set "$term_key" exec xdg-terminal-exec
        elif have wezterm; then
            gsettings set "$term_key" exec wezterm
        fi
    fi
fi
ok "Nemo is the file manager"
