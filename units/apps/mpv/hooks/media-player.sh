#!/usr/bin/env bash
# mpv as the handler of video and audio files.
. "$(dirname "$(readlink -f "$0")")/../../../lib/hook.sh"

for mime in video/mp4 video/x-matroska video/webm video/quicktime video/x-msvideo \
            video/mpeg video/ogg video/3gpp video/x-flv video/mp2t video/x-m4v \
            audio/mpeg audio/flac audio/ogg audio/x-wav audio/mp4 audio/aac \
            audio/opus audio/x-vorbis+ogg audio/webm; do
    xdg-mime default mpv.desktop "$mime"
done
ok "mpv opens video and audio"
