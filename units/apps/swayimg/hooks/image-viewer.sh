#!/usr/bin/env bash
# swayimg as the handler of image files.
. "$(dirname "$(readlink -f "$0")")/../../../lib/hook.sh"

for mime in image/png image/jpeg image/webp image/gif image/avif image/jxl \
            image/heif image/heic image/tiff image/bmp image/svg+xml image/x-tga \
            image/qoi image/x-portable-anymap; do
    xdg-mime default swayimg.desktop "$mime"
done
ok "swayimg opens images"
