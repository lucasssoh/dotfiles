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

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DEST_DIR="$HOME/.config/ccslide"

info "Setting up the ccslide workflow..."

# 1. Create the destination folder under ~/.config
mkdir -p "$DEST_DIR"

# Helper to link cleanly

# 2. Symlink the Python script and the Zsh config
safe_link "$DOTFILES_DIR/config/ccslide/ccslide.py"  "$DEST_DIR/ccslide.py"
safe_link "$DOTFILES_DIR/config/ccslide/ccslide.zsh" "$DEST_DIR/ccslide.zsh"

chmod +x "$DOTFILES_DIR/config/ccslide/ccslide.py"

# 3. mdp is the whole point of the module -- ccslide only generates the
#    markdown, mdp is what actually presents it. Package first (Fedora
#    ships it in Terra, Debian/Ubuntu in universe), source build as the
#    fallback: it is NOT in Arch's official repos, and a fresh Fedora has
#    no Terra either, so the package path cannot be relied on alone.
build_mdp_from_source() {
    info "Building mdp from source (https://github.com/visit1985/mdp)..."
    pkg_ensure git make gcc "$(pkg_pick ncurses-devel ncurses libncursesw5-dev)"

    local src_dir
    src_dir="$(mktemp -d)"
    # shellcheck disable=SC2064  # expand src_dir now, it is local to this call
    trap "rm -rf '$src_dir'" RETURN
    git clone --depth 1 https://github.com/visit1985/mdp.git "$src_dir"
    make -C "$src_dir"
    sudo_maybe make -C "$src_dir" install   # lands in /usr/local/bin/mdp
}

if command -v mdp &> /dev/null; then
    ok "mdp already installed ($(command -v mdp))"
else
    info "Installing mdp..."
    # pkg_ensure returns 0 even when it could not install, so the fallback is
    # keyed on the binary actually being there afterwards rather than on an
    # exit code.
    pkg_ensure mdp || true
    command -v mdp &> /dev/null || build_mdp_from_source
    command -v mdp &> /dev/null || { echo "mdp installation failed" >&2; exit 1; }
fi

ok "ccslide module installed to $DEST_DIR"
echo ""
echo "To enable the command, add this line at the end of your ~/.zshrc or shell startup file:"
echo "   source ~/.config/ccslide/ccslide.zsh"
