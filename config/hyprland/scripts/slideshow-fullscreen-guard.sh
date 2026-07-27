#!/usr/bin/env bash
# =========================================================
# slideshow-fullscreen-guard.sh — pauses the wallpaper slideshow (awww)
# while a window is fullscreen, to avoid render stutter behind a video or
# a game. Launched as a systemd --user service (see
# systemd/slideshow-fullscreen-guard.service).
# =========================================================

SOCKET=""
for i in $(seq 1 30); do
    SOCKET=$(find /run/user/$(id -u)/hypr/ -name ".socket2.sock" 2>/dev/null | head -1)
    [ -n "$SOCKET" ] && break
    sleep 1
done
[ -z "$SOCKET" ] && exit 1

socat -u UNIX-CONNECT:"$SOCKET" STDOUT | while IFS= read -r line; do
    EVENT=$(echo "$line" | cut -d'>' -f1)
    DATA=$(echo "$line" | sed 's/.*>>//')

    case "$EVENT" in
        fullscreen)
            if [ "$DATA" = "1" ]; then
                systemctl --user stop wallpaper-slideshow.service
            else
                systemctl --user start wallpaper-slideshow.service
            fi
            ;;
    esac
done
