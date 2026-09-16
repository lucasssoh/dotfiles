#!/usr/bin/env bash
# ============================================================
# Liseuse — install
# ============================================================
# Reading, centralised: one picker (SUPER+F), one renderer, one history,
# dark, and with the bar/notifications/idle-lock held off for the length
# of a session. See liseuse (the script) and zathurarc next to this file.
# ============================================================
set -Eeuo pipefail

# The single safe_link (scripts/lib/link.sh). It replaces the copy that used
# to live here: that one removed and re-created the link on every run, even
# when it was already correct. This one returns early, and records what it
# did so `cc-pkg-mng verify` can check it later.
. "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../../scripts/lib/link.sh"

# Package helper: queries before it installs, so an already-provisioned
# machine performs zero package-manager calls and never prompts for sudo.
. "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../../scripts/lib/pkg.sh"

GREEN="\e[32m"
YELLOW="\e[33m"
RESET="\e[0m"

ok()   { echo -e "${GREEN}[ OK ]${RESET}  $*"; }
warn() { echo -e "${YELLOW}[WARN]${RESET}  $*"; }

# ------------------------------------------------------------
# 1. Packages
# ------------------------------------------------------------
# zathura-pdf-mupdf is the one that makes a single reader viable: it
# registers as the handler for pdf, epub, mobi, fb2 AND oxps at once
# (`dnf repoquery --provides zathura-pdf-mupdf`), so every format lands
# in the same window with the same theme, keys and history file. The
# other two plugins extend that to comics and DjVu.
#
# NOT zathura-pdf-poppler: it would take over application/pdf from the
# mupdf plugin (they conflict on the same MIME type) and split PDFs off
# from everything else, which is precisely what this module exists to
# avoid.
#
# The last two are for `mutool info`, which the picker uses to turn a
# stored page number into "p. 42/380", and for notify-send. Both are
# optional in practice: without mutool the picker just shows "p. 42".
#
# mutool's package name is where the three distros actually diverge, and
# guessing it cost one failed install: `mupdf-tools` is the Debian and
# Arch name, Fedora ships the same binary in plain `mupdf` and has no
# `mupdf-tools` at all (`rpm -qf /usr/bin/mutool` -> mupdf-1.28.2). Hence
# a list per distro rather than one list with a substitution.
pkg_ensure zathura zathura-pdf-mupdf zathura-cb zathura-djvu \
    "$(pkg_pick mupdf mupdf-tools mupdf-tools)" \
    "$(pkg_pick libnotify libnotify libnotify-bin)"

# ------------------------------------------------------------
# 2. Symlinks
# ------------------------------------------------------------
DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MODULE_DIR="$DOTFILES_DIR/config/liseuse"


mkdir -p ~/.config/zathura ~/.config/liseuse ~/.local/bin

safe_link "$MODULE_DIR/zathurarc"    ~/.config/zathura/zathurarc
safe_link "$MODULE_DIR/sources.conf" ~/.config/liseuse/sources.conf

chmod +x "$MODULE_DIR/liseuse"
# Absolute path in the keybind, not a bare `liseuse`: processes launched
# by Hyprland don't inherit ~/.local/bin in their PATH (see commit
# bbb8f61 and the Prisme/Roue binds in hypr/keybinds.lua).
safe_link "$MODULE_DIR/liseuse" ~/.local/bin/liseuse

# ------------------------------------------------------------
# 3. Library root
# ------------------------------------------------------------
# Created rather than assumed: the picker needs somewhere obvious to drop
# a downloaded book. Everything else it reads is declared in
# sources.conf and stays where it already lives.
mkdir -p ~/Livres

# ------------------------------------------------------------
# 4. Default application for the formats zathura handles
# ------------------------------------------------------------
# So that opening a PDF from nemo, Firefox's download list or a terminal
# lands in the same reader with the same theme and, above all, the same
# history file -- which is what keeps the picker's "en cours" ranking
# honest about books opened outside SUPER+F.
#
# Points at zathura's own .desktop, not at a Liseuse one: a file opened
# from a file manager is not a reading SESSION (no bar hiding, no idle
# inhibitor), it's a quick look at a document.
if command -v xdg-mime &> /dev/null; then
    for mime in application/pdf application/epub+zip \
                application/x-mobipocket-ebook application/vnd.comicbook+zip \
                image/vnd.djvu; do
        xdg-mime default org.pwmt.zathura.desktop "$mime" 2>/dev/null || true
    done
    ok "zathura set as the default handler for PDF/EPUB/MOBI/CBZ/DjVu."
else
    warn "xdg-mime absent -- default handler not set."
fi

ok "Liseuse configured (SUPER+F). Library: ~/Livres + ~/.config/liseuse/sources.conf"
