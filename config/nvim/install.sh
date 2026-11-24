#!/usr/bin/env bash
set -Eeuo pipefail

# The single safe_link (scripts/lib/link.sh). It replaces the copy that used
# to live here: that one removed and re-created the link on every run, even
# when it was already correct. This one returns early, and records what it
# did so `cc-pkg-mng verify` can check it later.
. "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../../scripts/lib/link.sh"

# Package helper: queries before it installs, so an already-provisioned
# machine performs zero package-manager calls and never prompts for sudo.
. "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../../scripts/lib/pkg.sh"

BLUE="\e[34m"
GREEN="\e[32m"
RESET="\e[0m"

info() { echo -e "${BLUE}[INFO]${RESET}  $*"; }
ok()   { echo -e "${GREEN}[ OK ]${RESET}  $*"; }

# 1. Install Neovim if needed
pkg_ensure neovim

# 1b. Formules en ligne de l'aperçu markdown externe (bin/mdview).
pkg_ensure libtexprintf-tools

# 1c. PlantUML (ftplugin/plantuml.lua) : plantuml pour le lint, plantuml-lsp
# pour la complétion. Ce dernier n'est ni dans Mason ni dans un dépôt, et ne
# publie aucun binaire : seul `go install` le fournit. GOBIN vers
# ~/.local/bin plutôt que ~/go/bin, qui n'est pas dans le PATH.
pkg_ensure plantuml "$(pkg_pick golang go golang-go)"
# La fenêtre de l'aperçu en direct, bin/umview : GTK 4 et librsvg pilotés
# depuis Python (déjà là sur un bureau GNOME, pas forcément ailleurs).
# imv sert de secours sans GTK 4, Firefox en dernier recours.
pkg_ensure "$(pkg_pick python3-gobject python-gobject python3-gi)" \
    "$(pkg_pick python3-cairo python-cairo python3-gi-cairo)" \
    "$(pkg_pick gtk4 gtk4 gir1.2-gtk-4.0)" \
    "$(pkg_pick librsvg2 librsvg gir1.2-rsvg-2.0)" \
    imv
# L'aperçu markdown en direct, bin/mdview : même base GTK 4, plus la chaîne
# markdown de la liseuse (il lit config/liseuse/md2pdf.py sans le modifier),
# à installer ici aussi pour qu'il marche sans le module liseuse.
pkg_ensure "$(pkg_pick python3-markdown python-markdown python3-markdown)" \
    "$(pkg_pick python3-pymdown-extensions python-pymdown-extensions python3-pymdownx)" \
    "$(pkg_pick python3-pygments python-pygments python3-pygments)"
# Ses formules $$...$$ : config/liseuse/tex2svg.js, MathJax sous node. Le
# node_modules est celui de la liseuse (même raison que plus haut : qu'il
# marche sans ce module) ; les $...$ en ligne, eux, n'ont besoin que
# d'utftex, installé ci-dessus.
command -v node >/dev/null 2>&1 || pkg_ensure "$(pkg_pick nodejs nodejs nodejs)"
command -v npm >/dev/null 2>&1 || pkg_ensure "$(pkg_pick nodejs-npm npm npm)"
LISEUSE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../liseuse" && pwd)"
if [ ! -d "$LISEUSE_DIR/node_modules/mathjax-full" ] && command -v npm >/dev/null 2>&1; then
    npm ci --prefix "$LISEUSE_DIR" --omit=dev --no-audit --no-fund --silent \
        && ok "mathjax-full installed (mdview maths)." \
        || info 'npm ci failed: mdview shows $$...$$ as TeX source.'
fi
if ! command -v plantuml-lsp >/dev/null 2>&1 && [ ! -x ~/.local/bin/plantuml-lsp ]; then
    GOBIN="$HOME/.local/bin" go install github.com/ptdewey/plantuml-lsp@latest \
        && ok "plantuml-lsp installed." \
        || info "plantuml-lsp: go install failed, PlantUML completion disabled."
fi

# 2. Symlinks
DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
mkdir -p ~/.config/nvim


safe_link "$DOTFILES_DIR/config/nvim/init.lua" ~/.config/nvim/init.lua
safe_link "$DOTFILES_DIR/config/nvim/lua" ~/.config/nvim/lua
safe_link "$DOTFILES_DIR/config/nvim/ftplugin" ~/.config/nvim/ftplugin
safe_link "$DOTFILES_DIR/config/nvim/colors" ~/.config/nvim/colors
safe_link "$DOTFILES_DIR/config/nvim/bin" ~/.config/nvim/bin
ok "Neovim configured."
