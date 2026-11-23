#!/usr/bin/env bash
. "$(dirname "$(readlink -f "$0")")/../../../lib/hook.sh"

# The session's services hang off hyprland-session.target, which only
# Hyprland starts and stops. Up to 2.7.0 they hung off
# graphical-session.target, which any desktop starts: move the links of
# the ones enabled there.
#
# Not `systemctl reenable`: on a unit file that is itself a symlink, as
# cc-pkg-mng links them, its disable step removes the unit file too.
wants="$HOME/.config/systemd/user/graphical-session.target.wants"
systemctl --user daemon-reload
for s in balise manette pouls programme sesame wallpaper-slideshow; do
    if [[ -L "$wants/$s.service" ]]; then
        rm "$wants/$s.service"
        systemctl --user enable -q "$s.service"
        ok "$s starts with Hyprland only"
    fi
done
