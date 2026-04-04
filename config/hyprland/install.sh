#!/usr/bin/env bash
# ============================================================
# INSTALL.SH — Minimal Hyprland laptop setup
# Fedora / Arch / Debian-Ubuntu
# Uses symlinks so edits in the repo reflect live immediately
# ============================================================
RESET_MODE=false
[ "$1" = "--reset" ] && RESET_MODE=true

set -e

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
    sudo dnf copr enable -y solopasha/hyprland 2>/dev/null || true

    PKGS=(
        # Hyprland ecosystem
        hyprland hyprlock hypridle xdg-desktop-portal-hyprland
        # Bar / notifications / launcher
        waybar dunst rofi-wayland gsimplecal
        # Wallpaper daemon
        swww
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
        # Fonts (Nerd Fonts for Waybar icons)
        google-noto-sans-fonts google-noto-emoji-fonts jetbrains-mono-fonts-all
        # System deps (polkit-gnome doesn't exist on Fedora, polkit is pulled in as dep)
        polkit xdg-user-dirs brightnessctl playerctl
        # Screenshots
        grim slurp
        # Tools
        bc jq curl git lm_sensors unzip
        # Qt theming
        qt5ct qt6ct
    )

elif [ "$DISTRO" = "arch" ]; then
    PKGS=(
        # Hyprland ecosystem
        hyprland hyprlock hypridle xdg-desktop-portal-hyprland
        # Bar / notifications / launcher
        waybar dunst rofi-wayland gsimplecal
        # Wallpaper daemon
        swww
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
        # Fonts
        noto-fonts noto-fonts-emoji ttf-jetbrains-mono-nerd
        # System deps
        polkit-gnome xdg-user-dirs brightnessctl playerctl
        # Screenshots
        grim slurp
        # Tools
        bc jq curl git lm_sensors unzip
        # Qt
        qt5ct qt6ct
    )

elif [ "$DISTRO" = "debian" ]; then
    warn "Debian/Ubuntu: hyprland, swww and hyprlock may need manual install."
    PKGS=(
        hyprland
        waybar dunst rofi gsimplecal
        pipewire pipewire-pulse wireplumber pavucontrol
        network-manager network-manager-gnome
        blueman
        wl-clipboard
        xdg-desktop-portal-hyprland
        polkit-gnome xdg-user-dirs
        brightnessctl playerctl
        grim slurp
        papirus-icon-theme
        fonts-noto fonts-noto-color-emoji
        bc jq curl git lm-sensors unzip
        qt5ct
    )
fi

$PKG_INSTALL "${PKGS[@]}"
ok "Packages installed."

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
# SYMLINK CONFIG
# ============================================================

if [ "$RESET_MODE" = true ]; then
    warn "Reset mode enabled — removing old configs from $CONFIG"
    rm -rf "$CONFIG"/{hypr,waybar,rofi,dunst,hyprlock,hypridle,scripts,gsimplecal}
    ok "Old configs removed"
fi

section "Linking configuration directories"

# Define the folders to be linked as entire directories
# Based on your ls -R output
modules=("hypr" "waybar" "rofi" "dunst" "hyprlock" "hypridle" "scripts" "gsimplecal")

for mod in "${modules[@]}"; do
    if [ -d "$REPO_DIR/$mod" ]; then
        # Link the entire folder so new files are tracked automatically
        safe_link "$REPO_DIR/$mod" "$CONFIG/$mod"
    else
        warn "Source directory $mod not found in repo, skipping."
    fi
done

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

# 1️⃣ Create wallpaper directory
mkdir -p "$WALLPAPER_DIR"

# 2️⃣ Make scripts executable in the repo
chmod +x "$WP_SCRIPT" "$RESTORE_SCRIPT"

# 3️⃣ Symlink to ~/.local/bin (Make sure this is in your $PATH)
mkdir -p "$HOME/.local/bin"
ln -sfn "$WP_SCRIPT" "$HOME/.local/bin/set_wallpaper"
ln -sfn "$RESTORE_SCRIPT" "$HOME/.local/bin/restore_wallpaper"

# 4️⃣ Create a .desktop file so it appears in Rofi/App Launchers
mkdir -p "$HOME/.local/share/applications"
cat <<EOF > "$HOME/.local/share/applications/set_wallpaper.desktop"
[Desktop Entry]
Name=Set Wallpaper
Exec=set_wallpaper
Icon=background
Type=Application
Categories=Settings;
Terminal=false
EOF

ok "Wallpaper scripts ready and added to App Launcher."

# 5️⃣ Start swww-daemon ONLY if in a Wayland session and not already running
if [ -n "$WAYLAND_DISPLAY" ]; then
    if ! pgrep -x "swww-daemon" >/dev/null; then
        swww-daemon --format xrgb &
        sleep 1
        ok "swww-daemon started."
    fi
else
    info "Not in Wayland. swww-daemon will start with Hyprland later."
fi

# 6️⃣ Handle State File & Initial Wallpaper
if [ ! -f "$STATE_FILE" ] || [ ! -s "$STATE_FILE" ]; then
    # Find first image (supports jpg, png, jpeg, webp)
    FIRST_WP=$(find "$WALLPAPER_DIR" -type f \( -name "*.jpg" -o -name "*.png" -o -name "*.jpeg" -o -name "*.webp" \) | head -n 1)
    
    if [ -n "$FIRST_WP" ]; then
        echo "$FIRST_WP" > "$STATE_FILE"
        ok "Initial wallpaper registered: $(basename "$FIRST_WP")"
    else
        warn "No wallpapers found in $WALLPAPER_DIR."
    fi
fi

# 7️⃣ Apply wallpaper ONLY if Wayland and Daemon are active
if [ -n "$WAYLAND_DISPLAY" ] && pgrep -x "swww-daemon" >/dev/null; then
    bash "$RESTORE_SCRIPT"
    ok "Wallpaper applied."
else
    info "Wallpaper will be applied automatically when you launch Hyprland."
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
echo -e "${GREEN}${BOLD}✅ Done!${RESET}"
echo ""
echo "  Key bindings:"
echo "    Super + Enter     → WezTerm"
echo "    Super + W         ->Wallpapers"
echo "    Super + Space     → App launcher (Rofi)"
echo "    Super + E         → Thunar"
echo "    Super + B         → Firefox"
echo "    Super + L         → Lock screen"
echo "    Super + Q         → Close window"
echo "    Super + Shift + M → Exit Hyprland"
echo "    Super + Shift + R → Reload config"
echo "    3-finger swipe    → Switch workspace (trackpad)"
echo ""
echo "  Start Hyprland: Hyprland"
echo ""
