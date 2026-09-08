#!/usr/bin/env bash
set -Eeuo pipefail

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
safe_link() {
    local src=$1
    local dest=$2
    if [ -L "$dest" ] || [ -f "$dest" ]; then
        rm -rf "$dest"
    fi
    ln -s "$src" "$dest"
}

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
    if command -v dnf &> /dev/null; then
        sudo dnf install -y git make gcc ncurses-devel
    elif command -v pacman &> /dev/null; then
        sudo pacman -S --noconfirm --needed git make gcc ncurses
    elif command -v apt-get &> /dev/null; then
        sudo apt-get install -y git make gcc libncursesw5-dev
    fi

    local src_dir
    src_dir="$(mktemp -d)"
    # shellcheck disable=SC2064  # expand src_dir now, it is local to this call
    trap "rm -rf '$src_dir'" RETURN
    git clone --depth 1 https://github.com/visit1985/mdp.git "$src_dir"
    make -C "$src_dir"
    sudo make -C "$src_dir" install   # lands in /usr/local/bin/mdp
}

if command -v mdp &> /dev/null; then
    ok "mdp already installed ($(command -v mdp))"
else
    info "Installing mdp..."
    if command -v dnf &> /dev/null; then
        sudo dnf install -y mdp || build_mdp_from_source
    elif command -v pacman &> /dev/null; then
        sudo pacman -S --noconfirm mdp || build_mdp_from_source
    elif command -v apt-get &> /dev/null; then
        sudo apt-get install -y mdp || build_mdp_from_source
    else
        build_mdp_from_source
    fi
    command -v mdp &> /dev/null || { echo "mdp installation failed" >&2; exit 1; }
fi

ok "ccslide module installed to $DEST_DIR"
echo ""
echo "To enable the command, add this line at the end of your ~/.zshrc or shell startup file:"
echo "   source ~/.config/ccslide/ccslide.zsh"
