#!/usr/bin/env bash
set -uo pipefail

# =========================================================
# balise-autoclose.sh — closes Balise as soon as another window takes focus.
#
# INERT as things stand. It runs `balise hide`, which acts on the Rust
# crate's LEGACY GTK4 window, and nothing in the session opens that any
# more -- the panel you see is QML (quickshell/bar/modules/balise/), and
# it closes on an outside click via a native HyprlandFocusGrab (see
# shell.qml), which is the mechanism this script existed to substitute
# for. Still started from hypr/hyprland.lua so the GTK window behaves if
# it is ever opened by hand.
#
# Why it exists at all: that GTK window is a plain layer-shell surface,
# and GTK/gtk4-layer-shell never emits a focus-loss event for one (its
# "is-active" property never goes back to false). So this relies on
# Hyprland events (activewindow) instead, which are reliable. Opening the
# window itself never triggers an activewindow event (layer-shell
# surfaces don't appear in that stream), so this can't accidentally close
# it right after it opens.
# =========================================================

# ~/.local/bin (where install.sh places balise) isn't in the PATH of
# processes launched by Hyprland -- only the zsh profile adds it.
export PATH="$HOME/.local/bin:$PATH"

SOCKET=""
for _ in $(seq 1 30); do
    SOCKET=$(find "/run/user/$(id -u)/hypr/" -name ".socket2.sock" 2>/dev/null | head -1)
    [ -n "$SOCKET" ] && break
    sleep 1
done
[ -z "$SOCKET" ] && exit 1

socat -u UNIX-CONNECT:"$SOCKET" STDOUT | while IFS= read -r line; do
    case "$line" in
        activewindow\>\>*)
            balise hide >/dev/null 2>&1 || true
            ;;
    esac
done
