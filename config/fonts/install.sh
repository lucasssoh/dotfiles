#!/usr/bin/env bash
set -e

BLUE="\e[34m"
GREEN="\e[32m"
RESET="\e[0m"

info() { echo -e "${BLUE}[INFO]${RESET}  $*"; }
ok()   { echo -e "${GREEN}[ OK ]${RESET}  $*"; }

FONT_DIR="$HOME/.local/share/fonts"
mkdir -p "$FONT_DIR"

# List of fonts to install (exact names for the GitHub URL)
# Using an array so more can be added easily
FONTS=("JetBrainsMono" "Iosevka" "CascadiaCode")

for FONT in "${FONTS[@]}"; do
    # Check whether the font is already installed (case-insensitive with -i)
    if fc-list : family | grep -iq "$FONT"; then
        info "$FONT is already installed."
    else
        info "Downloading $FONT Nerd Font..."
        # Download straight into /tmp under the font's name
        curl -L "https://github.com/ryanoasis/nerd-fonts/releases/latest/download/${FONT}.zip" -o "/tmp/${FONT}.zip"

        info "Extracting $FONT..."
        # One subfolder per font to keep ~/.local/share/fonts tidy
        mkdir -p "$FONT_DIR/$FONT"
        unzip -o "/tmp/${FONT}.zip" -d "$FONT_DIR/$FONT"

        rm "/tmp/${FONT}.zip"
        ok "$FONT installed successfully."

        # Flag that the cache needs a refresh
        NEEDS_CACHE_RELOAD=true
    fi
done

# Only refresh the cache once at the end, if needed
if [ "$NEEDS_CACHE_RELOAD" = true ]; then
    info "Updating font cache..."
    fc-cache -fv
    ok "All fonts are ready."
else
    info "No new fonts to install."
fi
