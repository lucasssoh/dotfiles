#!/usr/bin/env bash
# Build ~/Images/Wallpapers from the repo (and the extra folders Prisme lists).
. "$(dirname "$(readlink -f "$0")")/../../../lib/hook.sh"

bash "$REPO/config/hyprland/set_wallpapers.sh"

mkdir -p "$HOME/.local/bin"
ln -sfn "$REPO/config/hyprland/scripts/restore_wallpaper.sh" "$HOME/.local/bin/restore_wallpaper"

# The wallpaper itself comes from ~/.config/hypr/wallpaper-playlist.json,
# written by Prisme (Super+W); a fresh machine has none until one is picked.
ok "wallpaper library ready"
