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

# 1b. Rendu des formules mathématiques dans le markdown (render-markdown.nvim
# délègue la conversion LaTeX -> unicode à un binaire externe).
#
# utftex rend en 2D -- a^2 devient a², \frac trace une vraie barre -- et c'est
# lui qui fait disparaître les « ^ », les « _ » et les « $ » du texte affiché.
# C'est la vraie dépendance ; sans elle, les formules restent en clair.
pkg_ensure libtexprintf-tools

# latex2text (pylatexenc) n'est dans aucun dépôt Fedora, d'où pipx plutôt que
# pkg_ensure. Il ne sert que de filet : sur les quelques commandes qu'utftex
# refuse, il sort une ligne d'unicode approximative plutôt que rien. Purement
# optionnel, donc jamais bloquant -- la liste de convertisseurs de
# lua/plugins/markdown.lua se filtre toute seule sur vim.fn.executable().
if command -v pipx >/dev/null 2>&1; then
    pipx install pylatexenc >/dev/null 2>&1 || true
fi

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
# bin/ : tex2utf, référencé par chemin absolu depuis lua/plugins/markdown.lua
# (vim.fn.stdpath("config") .. "/bin/tex2utf"), donc le lien est ce qui le rend
# atteignable -- il n'est volontairement pas dans ~/.local/bin.
safe_link "$DOTFILES_DIR/config/nvim/bin" ~/.config/nvim/bin
ok "Neovim configured."
