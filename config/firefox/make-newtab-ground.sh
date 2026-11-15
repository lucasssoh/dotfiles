#!/usr/bin/env bash
# Writes the new tab's ground at the end of userContent.css: coucou's
# Nuit pair as data: URIs, between two marker lines. about:newtab refuses
# file:// images, even from userContent.css, and the sheet can't @import
# another file, so the pictures have to live in it.
# Rerun after changing wallpapers/coucou-nuit-plis*.
#
#     config/firefox/make-newtab-ground.sh        (needs ImageMagick)
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
walls="$here/../../wallpapers"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
uri() {
    magick "$walls/$1.jxl" -resize 2560x1600 -quality 90 "$tmp/$1.webp"
    printf 'data:image/webp;base64,%s' "$(base64 -w0 "$tmp/$1.webp")"
}
sheet="$here/chrome/userContent.css"
begin="/* ---- the ground picture: written by make-newtab-ground.sh, do not edit ---- */"
{
    sed "/^\/\* ---- the ground picture: written by make-newtab-ground.sh/,\$d" "$sheet"
    echo "$begin"
    echo '@-moz-document url-prefix("about:newtab"), url-prefix("about:home") {'
    echo '    html:not(:has(> body:is(.lightWallpaper, .darkWallpaper))) {'
    echo "        background-image: url(\"$(uri coucou-nuit-plis-dark)\") !important;"
    echo '    }'
    echo '    @media (prefers-color-scheme: light) {'
    echo '        html:not(:has(> body:is(.lightWallpaper, .darkWallpaper))) {'
    echo "            background-image: url(\"$(uri coucou-nuit-plis)\") !important;"
    echo '        }'
    echo '    }'
    echo '}'
} > "$tmp/sheet.css"
cat "$tmp/sheet.css" > "$sheet"
echo "$sheet"
