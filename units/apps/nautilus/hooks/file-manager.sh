#!/usr/bin/env bash
# Nautilus as the file manager: directory handler, FileManager1 D-Bus name, captions.
. "$(dirname "$(readlink -f "$0")")/../../../lib/hook.sh"

# Folders go to Nautilus when the unit is first installed; on later runs
# only while no other installed app has them: that one was chosen.
current="$(xdg-mime query default inode/directory 2>/dev/null || true)"
if once folders || [ "$current" = org.gnome.Nautilus.desktop ] || ! desktop_installed "$current"; then
    mime="$HOME/.config/mimeapps.list"
    [ -f "$mime" ] && sed -i '/inode\/directory/d' "$mime"
    xdg-mime default org.gnome.Nautilus.desktop inode/directory
    # Nautilus answers org.freedesktop.FileManager1 itself; a redirect the
    # nemo unit left behind would send "Show in folder" to Nemo instead.
    service="$HOME/.local/share/dbus-1/services/org.freedesktop.FileManager1.service"
    [ -f "$service" ] && grep -q nemo "$service" && rm -f "$service"
    done_once folders
    ok "Nautilus is the file manager"
else
    info "Folders stay with ${current%.desktop}"
fi

if have gsettings; then
    # Only replace Nautilus's own default, never a value the user chose:
    # under each name, a folder's item count or a file's size.
    [ "$(gsettings get org.gnome.nautilus.icon-view captions)" = "['none', 'none', 'none']" ] \
        && gsettings set org.gnome.nautilus.icon-view captions "['size', 'none', 'none']"
fi
ok "Nautilus set up"
