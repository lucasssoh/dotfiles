#!/usr/bin/env bash
set -e

if ! command -v wireplumber &> /dev/null; then
    echo "[INFO] Installing WirePlumber..."
    if command -v dnf &> /dev/null; then
        sudo dnf install -y wireplumber pipewire-utils
    elif command -v pacman &> /dev/null; then
        sudo pacman -S --noconfirm wireplumber pipewire-utils
    elif command -v apt-get &> /dev/null; then
        sudo apt-get update && sudo apt-get install -y wireplumber pipewire-utils
    fi
fi

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SRC_DIR="$DOTFILES_DIR/config/wireplumber"
TARGET_DIR="$HOME/.config/wireplumber/wireplumber.conf.d"
SCRIPTS_TARGET="$HOME/.config/wireplumber/scripts"
SYSTEMD_TARGET="$HOME/.config/systemd/user"

mkdir -p "$TARGET_DIR" "$SCRIPTS_TARGET" "$SYSTEMD_TARGET"

safe_link() {
    local src=$1 dest=$2
    [ -L "$dest" ] || [ -f "$dest" ] && rm -rf "$dest"
    ln -s "$src" "$dest"
    echo "[OK] $dest -> $src"
}

safe_link "$SRC_DIR/10-bluetooth-policy.conf"  "$TARGET_DIR/10-bluetooth-policy.conf"
safe_link "$SRC_DIR/51-bluetooth-auto.conf"    "$TARGET_DIR/51-bluetooth-auto.conf"
safe_link "$SRC_DIR/52-bluetooth-profile.conf" "$TARGET_DIR/52-bluetooth-profile.conf"

safe_link "$SRC_DIR/systemd/bt-audio-switch.sh" "$SCRIPTS_TARGET/bt-audio-switch.sh"
chmod +x "$SCRIPTS_TARGET/bt-audio-switch.sh"

safe_link "$SRC_DIR/systemd/bt-audio-switch.service" "$SYSTEMD_TARGET/bt-audio-switch.service"

systemctl --user daemon-reload
systemctl --user enable --now bt-audio-switch.service

if systemctl --user is-active pipewire &> /dev/null; then
    echo "[INFO] Restarting audio stack..."
    systemctl --user restart wireplumber pipewire pipewire-pulse
fi

echo "[OK] WirePlumber configured"
