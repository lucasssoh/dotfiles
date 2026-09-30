#!/usr/bin/env bash
# ~/Livres, and Liseuse/zathura as the handlers of documents and Markdown.
. "$(dirname "$(readlink -f "$0")")/../../../lib/hook.sh"

mkdir -p "$HOME/Livres"
for mime in application/pdf application/epub+zip application/x-mobipocket-ebook \
            application/vnd.comicbook+zip image/vnd.djvu; do
    xdg-mime default org.pwmt.zathura.desktop "$mime"
done

apps="$HOME/.local/share/applications"
mkdir -p "$apps"
cat > "$apps/liseuse-markdown.desktop" <<DESKTOP
[Desktop Entry]
Type=Application
Name=Liseuse (Markdown)
Exec=$HOME/.local/bin/liseuse open %f
MimeType=text/markdown;
NoDisplay=true
Terminal=false
DESKTOP
update-desktop-database "$apps" 2>/dev/null || true
xdg-mime default liseuse-markdown.desktop text/markdown
ok "library ~/Livres, zathura for documents, Liseuse for Markdown"
