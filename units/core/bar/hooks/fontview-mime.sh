#!/usr/bin/env bash
# fontview as the handler of font files.
. "$(dirname "$(readlink -f "$0")")/../../../lib/hook.sh"

apps="$HOME/.local/share/applications"
mkdir -p "$apps"
cat > "$apps/fontview.desktop" <<DESKTOP
[Desktop Entry]
Type=Application
Name=fontview
Comment=Font viewer
Exec=$HOME/.local/bin/fontview %f
MimeType=font/sfnt;font/ttf;font/otf;font/collection;font/woff;font/woff2;application/x-font-ttf;application/x-font-otf;
Icon=font-x-generic
NoDisplay=true
Terminal=false
DESKTOP
update-desktop-database "$apps" 2>/dev/null || true
for mime in font/sfnt font/ttf font/otf font/collection font/woff font/woff2 application/x-font-ttf application/x-font-otf; do
    xdg-mime default fontview.desktop "$mime"
done
ok "fontview opens font files"
