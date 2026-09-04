#!/usr/bin/env bash
# ============================================================
# INSTALL.SH — Minimal Hyprland laptop setup
# Fedora / Arch / Debian-Ubuntu
# Uses symlinks so edits in the repo reflect live immediately
# ============================================================
RESET_MODE=false
[ "$1" = "--reset" ] && RESET_MODE=true

set -Eeuo pipefail

BOLD="\e[1m"
GREEN="\e[32m"
YELLOW="\e[33m"
RED="\e[31m"
BLUE="\e[34m"
RESET="\e[0m"

info()    { echo -e "${BLUE}[INFO]${RESET}  $*"; }
ok()      { echo -e "${GREEN}[ OK ]${RESET}  $*"; }
warn()    { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
err()     { echo -e "${RED}[ ERR]${RESET}  $*"; exit 1; }
section() { echo -e "\n${BOLD}── $* ──${RESET}\n"; }

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG="$HOME/.config"

# ============================================================
# SYMLINK HELPER
# safe_link <repo_path> <target_path>
# - Creates parent dirs as needed
# - Backs up existing files/dirs (not symlinks) to .bak
# - Skips if symlink already points to the right place
# ============================================================
safe_link() {
    local src="$1"   # absolute path inside the repo
    local dst="$2"   # absolute path where the symlink should live

    # Already correct symlink → nothing to do
    if [ -L "$dst" ] && [ "$(readlink -f "$dst")" = "$(readlink -f "$src")" ]; then
        info "Already linked: $dst"
        return
    fi

    # Existing file or dir (not a symlink) → back it up
    if [ -e "$dst" ] && [ ! -L "$dst" ]; then
        warn "Backing up existing: $dst → $dst.bak"
        mv "$dst" "$dst.bak"
    fi

    # Remove stale symlink pointing elsewhere
    [ -L "$dst" ] && rm "$dst"

    mkdir -p "$(dirname "$dst")"
    ln -s "$src" "$dst"
    ok "Linked: $dst → $src"
}

# ============================================================
# DETECT DISTRO
# ============================================================
section "Detecting distribution"

if command -v dnf &>/dev/null; then
    DISTRO="fedora"
    # --skip-unavailable: don't abort if a package doesn't exist or is already installed
    PKG_INSTALL="sudo dnf install -y --skip-unavailable"
    PKG_UPDATE="sudo dnf check-update -y || true"
    info "Fedora detected"
elif command -v pacman &>/dev/null; then
    DISTRO="arch"
    PKG_INSTALL="sudo pacman -S --noconfirm --needed"
    PKG_UPDATE="sudo pacman -Sy"
    info "Arch Linux detected"
elif command -v apt-get &>/dev/null; then
    DISTRO="debian"
    PKG_INSTALL="sudo apt-get install -y"
    PKG_UPDATE="sudo apt-get update"
    info "Debian/Ubuntu detected"
else
    err "Unsupported package manager."
fi

# ============================================================
# PACKAGES
# ============================================================
section "Installing packages"

$PKG_UPDATE

if [ "$DISTRO" = "fedora" ]; then
    sudo dnf copr enable -y lionheartp/Hyprland ||
        warn "COPR lionheartp/Hyprland could not be enabled — hyprland may fail to install."
    # Quickshell -- the actual bar (see quickshell/bar/), waybar/config.jsonc
    # is no longer started but stays installed/in the repo as a fallback,
    # same "kept but not started" pattern as dunst below.
    sudo dnf copr enable -y errornointernet/quickshell ||
        warn "COPR errornointernet/quickshell could not be enabled — quickshell may fail to install."

    PKGS=(
        # Hyprland ecosystem
        dbus-x11 dbus-daemon hyprland xdg-desktop-portal-hyprland
        # Bar / notifications / launcher
        # (SwayNotificationCenter replaces dunst as the active notification
        # daemon; dunst stays installed/available as a fallback, not started.
        # quickshell replaces waybar as the active bar the same way -- waybar
        # stays installed/available as a fallback, not started either)
        quickshell waybar dunst SwayNotificationCenter rofi-wayland khal hyprsunset
        # Wallpaper daemon
        awww
        # Network
        NetworkManager network-manager-applet nm-connection-editor
        # Bluetooth
        blueman bluez bluez-tools
        # Audio (pipewire-pulseaudio is the correct Fedora package name)
        pipewire pipewire-pulseaudio pipewire-alsa wireplumber pavucontrol
        # Clipboard
        wl-clipboard cliphist
        # Icons / theme
        papirus-icon-theme gnome-themes-extra gtk-murrine-engine adwaita-cursor-theme
        # Comix Cursors build deps (see "Building Comix Cursors" section below)
        librsvg2-tools xcursorgen
        # Fonts (Nerd Fonts for the bar/waybar icons)
        google-noto-sans-fonts google-noto-emoji-fonts jetbrains-mono-fonts-all
        # Font Awesome 6 (Free + Brands) -- quickshell/bar's Launchers.qml
        # (Steam/Discord logos) and Fonts.qml's iconSolid/iconBrand.
        # Straight Fedora repo package (verified: `dnf repoquery
        # --installed --qf '%{from_repo}'` on this machine reports plain
        # "fedora", no copr needed).
        fontawesome-6-free-fonts fontawesome-6-brands-fonts
        # System deps (polkit-gnome doesn't exist on Fedora, polkit is pulled in as dep)
        polkit xdg-user-dirs brightnessctl playerctl
        # Screenshots
        satty grim slurp grimblast
        # Tools
        bc jq curl git lm_sensors unzip socat
        # Qt theming
        qt5ct qt6ct
        # Orbit (WiFi/Bluetooth/VPN manager) build deps -- no Fedora package,
        # built from source further down in this script
        rust cargo gtk4-devel gtk4-layer-shell-devel NetworkManager-libnm-devel bluez-libs-devel
    )

elif [ "$DISTRO" = "arch" ]; then
    PKGS=(
        # Hyprland ecosystem
        dbus hyprland hyprlock hypridle xdg-desktop-portal-hyprland xdg-desktop-portal-gtk
        # Bar / notifications / launcher
        # quickshell is the active bar (see quickshell/bar/); waybar stays
        # installed as a fallback, not started -- same pattern as dunst
        quickshell waybar dunst swaync rofi-wayland khal hyprsunset
        # Wallpaper daemon
        awww
        # Network
        networkmanager network-manager-applet nm-connection-editor
        # Bluetooth
        blueman bluez bluez-utils
        # Audio
        pipewire pipewire-pulse pipewire-alsa wireplumber pavucontrol
        # Clipboard
        wl-clipboard cliphist
        # Icons / cursors
        papirus-icon-theme bibata-cursor-theme
        # Comix Cursors build deps (see "Building Comix Cursors" section below)
        librsvg xorg-xcursorgen
        # Fonts
        noto-fonts noto-fonts-emoji ttf-jetbrains-mono-nerd
        # System deps
        polkit-gnome xdg-user-dirs brightnessctl playerctl
        # Screenshots
        satty grim slurp
        # Tools
        bc jq curl git lm_sensors unzip socat
        # Qt
        qt5ct qt6ct
        # Orbit build deps
        rust cargo gtk4-layer-shell libnm bluez-libs
    )

elif [ "$DISTRO" = "debian" ]; then
    warn "Debian/Ubuntu: hyprland, swww and hyprlock may need manual install."
    warn "swaync (SwayNotificationCenter) is often not packaged in apt — install manually if 'swaync' isn't found."
    warn "quickshell (the active bar, see quickshell/bar/) is not packaged in apt — build from source (https://quickshell.org/docs/v0.3.0/guide/install-setup/) or install manually. waybar is still installed below as a fallback, just not started."
    warn "Orbit build deps (rust/cargo, libgtk4-layer-shell-dev, libnm-dev, libbluetooth-dev) vary a lot across Debian/Ubuntu versions — install manually if the cargo build step below fails."
    warn "xcursorgen ships in the x11-apps meta-package on Debian/Ubuntu (pulls in xeyes/xclock etc. as a side effect) — install it standalone if you'd rather avoid that."
    PKGS=(
        dbus dbus-x11 hyprland
        waybar dunst rofi khal hyprsunset
        pipewire pipewire-pulse wireplumber pavucontrol
        network-manager network-manager-gnome
        blueman
        wl-clipboard
        xdg-desktop-portal-hyprland xdg-desktop-portal-gtk
        polkit-gnome xdg-user-dirs
        brightnessctl playerctl
        satty grim slurp
        papirus-icon-theme
        # Comix Cursors build deps (see "Building Comix Cursors" section below)
        librsvg2-bin x11-apps
        fonts-noto fonts-noto-color-emoji
        bc jq curl git lm-sensors unzip socat
        qt5ct
    )
fi

$PKG_INSTALL "${PKGS[@]}"
ok "Packages installed."

if [ "$DISTRO" = "fedora" ]; then
    # --skip-unavailable means a COPR failure above can silently drop
    # hyprland/quickshell from the install instead of failing it -- verify
    # the two non-negotiable pieces actually landed rather than reporting
    # success regardless. (Not checked on Arch/Debian: those branches don't
    # use --skip-unavailable, and Debian's quickshell gap is already an
    # acknowledged manual step, see the warn above.)
    command -v Hyprland >/dev/null 2>&1 || err "Hyprland did not install (COPR unavailable?)."
    command -v quickshell >/dev/null 2>&1 || err "quickshell did not install (COPR unavailable?)."
fi

# Font Awesome 6 -- quickshell/bar's Launchers.qml (Steam/Discord logos)
# and Fonts.qml's iconSolid/iconBrand. Fedora's fontawesome-6-free-fonts/
# fontawesome-6-brands-fonts are already in the main PKGS array above
# (verified: plain "fedora" repo, no copr). Kept OUT of Arch's PKGS array
# on purpose and installed here instead, isolated: ttf-font-awesome is
# the standard `extra` repo package as of writing but wasn't verified on
# an actual Arch install (this machine is Fedora) -- `pacman -S` aborts
# the WHOLE command on one unknown package name (unlike dnf's
# --skip-unavailable), so a wrong guess here must not be able to take the
# rest of PKGS down with it. Debian/Ubuntu: no attempt -- FA6 generally
# isn't packaged there yet, get it from https://fontawesome.com/download.
if [ "$DISTRO" = "arch" ]; then
    sudo pacman -S --noconfirm --needed ttf-font-awesome \
        || warn "ttf-font-awesome install failed/not found -- get Font Awesome 6 manually: https://fontawesome.com/download (Steam/Discord icons and some bar glyphs need it)."
elif [ "$DISTRO" = "debian" ]; then
    warn "Font Awesome 6 isn't reliably packaged for Debian/Ubuntu yet -- install manually if Launchers.qml's Steam/Discord icons or other bar glyphs come up blank: https://fontawesome.com/download"
fi

# ============================================================
# BALISE (native Wayland WiFi/Bluetooth/Ethernet manager)
# ============================================================
# First-party, written for this setup (balise-src/) -- replaces Orbit,
# which was a vendored third-party app patched around repeatedly. Same
# build pattern as Prisme/Roue below: copy the crate to a cache dir,
# cargo build, install the binary to ~/.local/bin (no sudo needed).
# Config + theme live in config/hyprland/balise/ and are symlinked
# further down like the other module directories, so style.css can be
# edited and reloaded with `balise reload-theme` without recompiling.
#
# No VPN support, by design.
section "Building Balise (WiFi/Bluetooth/Ethernet manager)"

BALISE_BUILD="$HOME/.cache/balise-build"

if ! command -v cargo &>/dev/null; then
    warn "cargo not found — skipping Balise build. Install a Rust toolchain and re-run this script to get it."
else
    rm -rf "$BALISE_BUILD"
    mkdir -p "$BALISE_BUILD"
    cp -r "$REPO_DIR/balise-src/." "$BALISE_BUILD/"

    if (cd "$BALISE_BUILD" && cargo build --release); then
        mkdir -p "$HOME/.local/bin"
        install -Dm755 "$BALISE_BUILD/target/release/balise" "$HOME/.local/bin/balise"
        ok "Balise built and installed to ~/.local/bin/balise."
    else
        warn "Balise build failed — the bar's WiFi/Bluetooth/Ethernet clicks will fall back to nmtui/blueman-manager until this is fixed."
    fi
fi

# ============================================================
# PRISME (native Wayland wallpaper picker)
# ============================================================
# Same logic as the Balise block above: source lives in this repo
# (prisme-src/), built at install time, binary in ~/.local/bin. Config (CSS
# theme) in config/hyprland/prisme/, symlinked further down like the other
# directories. awww stays the application backend (unchanged); Prisme only
# replaces the selection UI (previously rofi).
#
# `cargo build --release` also builds wallpaper-filter (src/bin/), the
# native worker for the "Filtered" cache (smart crop/extend, replaces the
# old wallpaper-filter-one.sh + ImageMagick) -- same crate, same
# dependencies (including `image`, already used for the thumbnails),
# installed to the same place.
section "Building Prisme (wallpaper picker)"

PRISME_BUILD="$HOME/.cache/prisme-build"

if ! command -v cargo &>/dev/null; then
    warn "cargo not found — skipping Prisme build. Install a Rust toolchain and re-run this script to get it."
else
    rm -rf "$PRISME_BUILD"
    mkdir -p "$PRISME_BUILD"
    cp -r "$REPO_DIR/prisme-src/." "$PRISME_BUILD/"

    if (cd "$PRISME_BUILD" && cargo build --release); then
        mkdir -p "$HOME/.local/bin"
        install -Dm755 "$PRISME_BUILD/target/release/prisme" "$HOME/.local/bin/prisme"
        install -Dm755 "$PRISME_BUILD/target/release/wallpaper-filter" "$HOME/.local/bin/wallpaper-filter"
        ok "Prisme and wallpaper-filter built and installed to ~/.local/bin/."
    else
        warn "Prisme build failed — Super+W will fail to launch, and the 'Filtered' wallpaper cache will stop updating, until this is fixed."
    fi
fi

# ============================================================
# ROUE (RPG weapon-menu-style radial selection wheel)
# ============================================================
# Same logic as the Orbit/Prisme blocks above: source vendored in this repo
# (roue-src/), built at install time, single binary in ~/.local/bin/roue.
# Replaces waybar/scripts/rofi-power.sh and rofi-performance.sh -- one
# binary for all wheels, each defined by a TOML file in
# config/hyprland/roue/wheels/ (symlinked further down like the other
# directories), so more can be added later without recompiling.
section "Building Roue (radial selection wheel)"

ROUE_BUILD="$HOME/.cache/roue-build"

if ! command -v cargo &>/dev/null; then
    warn "cargo not found — skipping Roue build. Install a Rust toolchain and re-run this script to get it."
else
    rm -rf "$ROUE_BUILD"
    mkdir -p "$ROUE_BUILD"
    cp -r "$REPO_DIR/roue-src/." "$ROUE_BUILD/"

    if (cd "$ROUE_BUILD" && cargo build --release); then
        mkdir -p "$HOME/.local/bin"
        install -Dm755 "$ROUE_BUILD/target/release/roue" "$HOME/.local/bin/roue"
        ok "Roue built and installed to ~/.local/bin/roue."
    else
        warn "Roue build failed — Super+Delete and the power profile menu will fail to launch until this is fixed."
    fi
fi

# ============================================================
# COMIX CURSORS (comic-style cursor theme)
# ============================================================
# No distro package -- built from the upstream SVG sources with
# rsvg-convert + xcursorgen (installed above). Not vendored like
# Balise/Prisme/Roue since this is a purely cosmetic asset pack, not
# something the desktop depends on functionally: if upstream ever
# disappears, re-running this script without network just skips the
# build and hypr/hyprland.lua's XCURSOR_THEME falls back to whatever
# theme is already on disk (or a stock one if never built before).
# "White" = white gloves / black outline, the classic Mickey Mouse
# look; hypr/hyprland.lua sets XCURSOR_THEME to ComixCursors-White.
# CURSORTRANS is patched to 0 below (upstream default is 0.3, a
# semi-transparent glove) -- fully opaque looks better at large sizes.
section "Building Comix Cursors (comic-style cursor theme)"

COMIX_BUILD="$HOME/.cache/comixcursors-build"
COMIX_THEME_NAME="White"   # Other variants: Black, Blue, Green, Orange, Red

if ! command -v rsvg-convert &>/dev/null || ! command -v xcursorgen &>/dev/null; then
    warn "rsvg-convert/xcursorgen not found — skipping Comix Cursors build."
elif [ -d "$HOME/.icons/ComixCursors-$COMIX_THEME_NAME" ]; then
    info "Comix Cursors ($COMIX_THEME_NAME) already installed, skipping."
else
    rm -rf "$COMIX_BUILD"
    if git clone --depth 1 https://gitlab.com/limitland/comixcursors.git "$COMIX_BUILD" 2>/dev/null; then
        sed -i 's/^CURSORTRANS=.*/CURSORTRANS=0/' "$COMIX_BUILD/ComixCursorsConfigs/$COMIX_THEME_NAME.CONFIG"
        if (cd "$COMIX_BUILD" && MULTISIZE=true THEMENAME="$COMIX_THEME_NAME" ./bin/build-cursors && make && make install); then
            ok "Comix Cursors ($COMIX_THEME_NAME) installed to ~/.icons/ComixCursors-$COMIX_THEME_NAME."
        else
            warn "Comix Cursors build failed — falling back to whatever cursor theme is already installed."
        fi
    else
        warn "Could not clone Comix Cursors (no network?) — skipping."
    fi
fi

# ============================================================
# SYSTEMD USER SERVICES
# ============================================================
section "Enabling services"

systemctl --user enable --now pipewire pipewire-pulse wireplumber 2>/dev/null || true
ok "Pipewire running."

if [ "$DISTRO" != "debian" ]; then
    sudo systemctl enable --now bluetooth 2>/dev/null || true
    ok "Bluetooth enabled."
fi

# Custom systemd --user services from the repo (balise.service, etc.)
SYSTEMD_DST="$HOME/.config/systemd/user"
mkdir -p "$SYSTEMD_DST"

if [ -d "$REPO_DIR/systemd" ]; then
    info "Linking and enabling custom systemd services..."

    # Symlink + enable each .service file found under systemd/
    find "$REPO_DIR/systemd" -type f -name "*.service" | while read -r service_file; do
        SERVICE_NAME=$(basename "$service_file")

        safe_link "$service_file" "$SYSTEMD_DST/$SERVICE_NAME"

        systemctl --user daemon-reload
        systemctl --user enable "$SERVICE_NAME"
        ok "Systemd service enabled: $SERVICE_NAME"
    done
else
    warn "No 'systemd' directory found in the repo, skipping."
fi

# ============================================================
# NERD FONTS CHECK
# ============================================================
section "Checking Nerd Fonts"

if fc-list | grep -qi "nerd"; then
    ok "Nerd Fonts already installed."
else
    warn "No Nerd Font detected — Waybar icons may not render correctly."
    info "Downloading JetBrains Mono Nerd Font..."
    mkdir -p ~/.local/share/fonts
    FONT_URL="https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.zip"
    if command -v curl &>/dev/null; then
        curl -fLo /tmp/JetBrainsMono.zip "$FONT_URL" \
        && unzip -o /tmp/JetBrainsMono.zip -d ~/.local/share/fonts/JetBrainsMono/ \
        && fc-cache -fv \
        && ok "JetBrains Mono Nerd Font installed." \
        || warn "Font download failed. Install manually: https://www.nerdfonts.com"
    else
        warn "curl not available. Install a Nerd Font manually:"
        warn "https://www.nerdfonts.com/font-downloads"
    fi
fi

# ============================================================
# WEZTERM FONT (GoogleSansCode Nerd Font Mono)
# ============================================================
section "Checking WezTerm font"

if fc-list | grep -qi "GoogleSansCode Nerd Font Mono"; then
    ok "GoogleSansCode Nerd Font Mono already installed."
else
    info "Downloading GoogleSansCode Nerd Font Mono (config/wezterm/wezterm.lua's config.font)..."
    mkdir -p ~/.local/share/fonts/GoogleSansCode
    FONT_URL="https://github.com/E-Vertin/GoogleSansCode-NerdFont/releases/download/v7.000/GoogleSansCode-NFM-v7.000.tar.xz"
    if command -v curl &>/dev/null; then
        curl -fLo /tmp/GoogleSansCode-NFM.tar.xz "$FONT_URL" \
        && tar -xf /tmp/GoogleSansCode-NFM.tar.xz -C ~/.local/share/fonts/GoogleSansCode/ \
        && fc-cache -f ~/.local/share/fonts \
        && ok "GoogleSansCode Nerd Font Mono installed." \
        || warn "Font download failed. Install manually: https://github.com/E-Vertin/GoogleSansCode-NerdFont/releases"
    else
        warn "curl not available. Install GoogleSansCode Nerd Font Mono manually:"
        warn "https://github.com/E-Vertin/GoogleSansCode-NerdFont/releases"
    fi
fi

# ============================================================
# PHOSPHOR ICONS (quickshell bar icons -- Fonts.qml's iconPhosphor)
# ============================================================
# MIT-licensed (verified via its own LICENSE file), not packaged by any
# distro -- pulled from the official @phosphor-icons/web npm package the
# same way it was first installed for this bar (see quickshell/bar/
# theme/Fonts.qml's own header comment for why Phosphor over Font
# Awesome/Nerd Fonts/SF Symbols). 6 separate TTFs (thin/light/regular/
# bold/fill/duotone), each its OWN font family, not one variable font
# with a weight axis -- copied flat into ~/.local/share/fonts, no
# subfolder, matching how they were installed originally.
section "Checking Phosphor Icons font"

if fc-list | grep -qi "Phosphor"; then
    ok "Phosphor Icons already installed."
elif ! command -v curl &>/dev/null || ! command -v jq &>/dev/null; then
    warn "curl/jq not available. Install Phosphor Icons manually:"
    warn "https://github.com/phosphor-icons/web"
else
    info "Downloading Phosphor Icons (@phosphor-icons/web, latest)..."
    PHOSPHOR_TMP="$(mktemp -d)"
    # `|| true`: this is a best-effort optional download (see the graceful
    # "install manually" fallback below) -- under `pipefail`, a curl failure
    # here (network down, registry unreachable) would otherwise make this
    # assignment itself fail and, since it's not inside an if/&&/||, take
    # the *entire* install script down with it via `set -e`.
    PHOSPHOR_VERSION="$(curl -fsL https://registry.npmjs.org/@phosphor-icons/web \
        | jq -r '."dist-tags".latest' 2>/dev/null)" || true

    if [ -n "$PHOSPHOR_VERSION" ] && [ "$PHOSPHOR_VERSION" != "null" ] \
        && curl -fLo "$PHOSPHOR_TMP/phosphor.tgz" \
            "https://registry.npmjs.org/@phosphor-icons/web/-/web-${PHOSPHOR_VERSION}.tgz" \
        && tar -xzf "$PHOSPHOR_TMP/phosphor.tgz" -C "$PHOSPHOR_TMP"; then
        mkdir -p ~/.local/share/fonts
        for weight_dir in thin light regular bold fill duotone; do
            find "$PHOSPHOR_TMP/package/src/$weight_dir" -maxdepth 1 -name "*.ttf" \
                -exec cp {} ~/.local/share/fonts/ \;
        done
        fc-cache -f ~/.local/share/fonts
        ok "Phosphor Icons ($PHOSPHOR_VERSION) installed."
    else
        warn "Phosphor Icons download failed. Install manually: https://github.com/phosphor-icons/web"
    fi
    rm -rf "$PHOSPHOR_TMP"
fi

# ============================================================
# SYMLINK CONFIG
# ============================================================

if [ "$RESET_MODE" = true ]; then
    warn "Reset mode enabled — removing old configs from $CONFIG"
    rm -rf "$CONFIG"/{hypr,waybar,quickshell,rofi,dunst,swaync,balise,prisme,roue,hyprlock,scripts,khal}
    ok "Old configs removed"
fi

section "Linking configuration directories"

# Config directories to fully symlink into ~/.config
modules=("hypr" "waybar" "quickshell" "rofi" "dunst" "swaync" "balise" "prisme" "roue" "hyprlock" "scripts" "khal" "theme")

for mod in "${modules[@]}"; do
    if [ -d "$REPO_DIR/$mod" ]; then
        # Link the entire folder so new files are tracked automatically
        safe_link "$REPO_DIR/$mod" "$CONFIG/$mod"
    else
        warn "Source directory $mod not found in repo, skipping."
    fi
done
# ── Hypr scripts ─────────────────────────────────────────────
section "Linking hypr scripts"

SCRIPTS_SRC="$REPO_DIR/scripts"
SCRIPTS_DST="$HOME/.config/hypr/scripts"
mkdir -p "$SCRIPTS_DST"

find "$SCRIPTS_SRC" -maxdepth 1 -name "*.sh" | while read -r script; do
    safe_link "$script" "$SCRIPTS_DST/$(basename "$script")"
done

# Prune links whose target no longer exists. Linking alone never removes
# anything, so every script renamed or deleted in the repo left a dangling
# symlink here forever -- hyprland.lua would then silently exec a
# nonexistent path. Found the hard way when orbit-autoclose.sh became
# balise-autoclose.sh, alongside four older leftovers.
pruned=0
while IFS= read -r stale; do
    rm -f "$stale"
    pruned=$((pruned + 1))
done < <(find "$SCRIPTS_DST" -maxdepth 1 -xtype l 2>/dev/null)
[ "$pruned" -gt 0 ] && ok "Removed $pruned dangling script symlink(s)."

ok "Hypr scripts linked."

# Handle standalone scripts in the root of your repo (like set_wallpapers.sh)
if [ -f "$REPO_DIR/set_wallpapers.sh" ]; then
    chmod +x "$REPO_DIR/set_wallpapers.sh"
    # Optional: link it to a bin folder or leave it in the repo
fi

# Ensure all scripts inside the repo are executable
# Since the folders are symlinked, this makes them executable in ~/.config too
find "$REPO_DIR" -type f -name "*.sh" -exec chmod +x {} +

ok "All directories linked. Changes in the repo are now live."

# ============================================================
# TEMPERATURE SENSOR
# ============================================================
section "CPU temperature sensor"

if command -v sensors &>/dev/null; then
    sudo sensors-detect --auto 2>/dev/null || true
    info "Run this to identify your sensor:"
    echo ""
    echo "    bash ~/.config/waybar/scripts/detect-temp.sh"
    echo ""
    info "Then set 'hwmon-path' in ~/.config/waybar/config if needed."
else
    warn "lm_sensors not found, skipping temperature detection."
fi

# ============================================================
# WALLPAPER SETUP & ROFI INTEGRATION
# ============================================================

section "Wallpaper automation"

WP_SCRIPT="$REPO_DIR/scripts/set_wallpaper.sh"
RESTORE_SCRIPT="$REPO_DIR/scripts/restore_wallpaper.sh"
STATE_FILE="$HOME/.cache/current_wallpaper"
WALLPAPER_DIR="$HOME/Images/Wallpapers"

# 1. Create wallpaper directory
mkdir -p "$WALLPAPER_DIR"

# 2. Make scripts executable in the repo
chmod +x "$WP_SCRIPT" "$RESTORE_SCRIPT"

# 3. Symlink to ~/.local/bin (must be in $PATH for the desktop entry below)
mkdir -p "$HOME/.local/bin"
ln -sfn "$WP_SCRIPT" "$HOME/.local/bin/set_wallpaper"
ln -sfn "$RESTORE_SCRIPT" "$HOME/.local/bin/restore_wallpaper"

# 4. Desktop entry using the absolute path, so it works from any launcher
mkdir -p "$HOME/.local/share/applications"
cat <<EOF > "$HOME/.local/share/applications/set_wallpaper.desktop"
[Desktop Entry]
Name=Set Wallpaper
Exec=$HOME/.local/bin/set_wallpaper
Icon=background
Type=Application
Categories=Settings;
Terminal=false
EOF

ok "Wallpaper scripts ready and added to App Launcher."

# Start awww daemon ONLY if in a Wayland session and not already running.
# WAYLAND_DISPLAY is legitimately absent (not just empty) when this script
# runs from a plain TTY before any session exists -- ${VAR:-} keeps that
# safe under `set -u`.
if [ -n "${WAYLAND_DISPLAY:-}" ]; then
    if ! pgrep -x "awww-daemon" >/dev/null; then
        awww-daemon &
        sleep 1
        ok "awww-daemon started."
    else
        info "awww-daemon already running."
    fi
else
    info "Not in Wayland. awww-daemon will start with Hyprland later."
fi

# 5. Handle State File & Initial Wallpaper
if [ ! -f "$STATE_FILE" ] || [ ! -s "$STATE_FILE" ]; then
    FIRST_WP=$(find "$WALLPAPER_DIR" -type f \( \
        -name "*.jpg" -o -name "*.png" -o -name "*.jpeg" -o -name "*.webp" \
    \) | head -n 1)

    if [ -n "$FIRST_WP" ]; then
        echo "$FIRST_WP" > "$STATE_FILE"
        ok "Initial wallpaper registered: $(basename "$FIRST_WP")"
    else
        warn "No wallpapers found in $WALLPAPER_DIR."
    fi
fi

# 6. Apply wallpaper (awww version)
if [ -n "${WAYLAND_DISPLAY:-}" ] && pgrep -x "awww-daemon" >/dev/null; then
    if [ -f "$STATE_FILE" ]; then
        CURRENT_WP=$(cat "$STATE_FILE")

        if [ -f "$CURRENT_WP" ]; then
            awww img "$CURRENT_WP"
            ok "Wallpaper applied via awww."
        else
            warn "State file points to invalid wallpaper."
        fi
    else
        info "No state file found, skipping wallpaper apply."
    fi
else
    info "Wallpaper will be applied automatically when awww-daemon starts."
fi
# ============================================================
# MONITORS
# ============================================================
section "Monitors"

info "After launching Hyprland, check your output names:"
echo ""
echo "    hyprctl monitors"
echo ""
info "Then adjust if needed: $REPO_DIR/hypr/monitors.conf"
info "(changes take effect immediately — it's symlinked)"

# ============================================================
# DONE
# ============================================================
echo ""
echo -e "${GREEN}${BOLD}Done.${RESET}"
echo ""
echo "  Key bindings:"
echo "    Super + Enter     → WezTerm"
echo "    Super + W         → Wallpapers"
echo "    Super + Space     → App launcher (Rofi)"
echo "    Super + E         → Nemo"
echo "    Super + B         → Firefox"
echo "    Super + Esc       → Lock screen"
echo "    Super + Q         → Close window"
echo "    Super + Shift + M → Exit Hyprland"
echo "    Super + Shift + R → Reload config"
echo "    3-finger swipe    → Switch workspace (trackpad)"
echo ""
echo "  Start Hyprland: Hyprland"
echo ""
