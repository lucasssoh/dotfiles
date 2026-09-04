#!/usr/bin/env bash
set -Eeuo pipefail

BLUE="\e[34m"
GREEN="\e[32m"
RESET="\e[0m"

info() { echo -e "${BLUE}[INFO]${RESET}  $*"; }
ok()   { echo -e "${GREEN}[ OK ]${RESET}  $*"; }

FONT_DIR="$HOME/.local/share/fonts"
mkdir -p "$FONT_DIR"

# Must be initialized: read unconditionally below, and with `set -u` an
# unset read is a hard error, not just an empty string.
NEEDS_CACHE_RELOAD=false

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
