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
    # is no longer started but stays installed/in the repo as a fallback.
    sudo dnf copr enable -y errornointernet/quickshell ||
        warn "COPR errornointernet/quickshell could not be enabled — quickshell may fail to install."
    # satty is NOT in any Fedora repo and never has been, so listing it in
    # PKGS below only ever got it skipped by --skip-unavailable -- silently,
    # module still exit=0. It backs Super+S / Super+SHIFT+S (hypr/keybinds.lua
    # pipes grim into it) and waybar/scripts/screenshot-region.sh; without it
    # the pipe breaks and a screenshot produces nothing.
    sudo dnf copr enable -y mineiro/satty ||
        warn "COPR mineiro/satty could not be enabled — Super+S screenshots will be broken."

    PKGS=(
        # Hyprland ecosystem.
        # hyprlock/hypridle are SEPARATE rpms on Fedora, not dependencies of
        # hyprland -- they were only ever in the Arch list below, so a fresh
        # Fedora install ended up with Super+Esc (hyprlock.conf is linked and
        # bound) pointing at a binary that wasn't there.
        dbus-x11 dbus-daemon hyprland hyprlock hypridle xdg-desktop-portal-hyprland
        # Backs the dialogs Hyprland shells out to; without it every startup
        # raises "Your system does not have hyprland-guiutils installed".
        # Upstream renamed this from hyprland-qtutils.
        hyprland-guiutils
        # Bar / notifications / launcher
        # quickshell is the active bar AND the active notification daemon
        # (see quickshell/bar/services/NotificationState.qml) -- waybar
        # stays installed/available as a fallback, not started. No
        # separate notification daemon package needed any more (used to
        # be SwayNotificationCenter, before that dunst).
        # fuzzel is the actual app launcher (Super+Space, see
        # hypr/keybinds.lua); rofi is kept for the cliphist picker (Super+V)
        # and its .rasi themes. config/fuzzel/ has its own module for the
        # config file -- listed here too so a standalone run of this script
        # still yields a usable desktop.
        quickshell waybar fuzzel rofi-wayland khal hyprsunset
        # Wallpaper daemon
        awww
        # Backs `powerprofilesctl`, which waybar/scripts/performance.sh calls
        # for the Super+Shift+Delete power-profile wheel. Used to arrive only
        # as a side effect of the KDE module, so skipping KDE silently broke
        # that wheel.
        power-profiles-daemon
        # Backs Quickshell.Services.UPower, i.e. the bar's whole battery
        # module (quickshell/bar/modules/Battery.qml) and its low-battery
        # alert -- both read UPower.displayDevice over DBus, never sysfs,
        # so with no upowerd running there is no device and the module
        # simply hides itself. Exactly the same story as
        # power-profiles-daemon above: it is present on the existing
        # machines only as a transitive dep (of waybar and thermald,
        # verified with `dnf repoquery --whatrequires`), which is a
        # guarantee that expires the day waybar is dropped for quickshell
        # -- and which a Fedora "Minimal Install" with no desktop
        # environment to drag it in never had in the first place.
        upower
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
        # hypr/scripts/idle-action.sh's dpms-off/dpms-on. Its header already
        # explains why the Hyprland dispatcher is not trusted here (it reports
        # ok without changing .dpmsStatus); wlopm speaks
        # wlr-output-power-management and does only this. Plain fedora repo,
        # no copr -- verified wlopm-1.0.0-4.fc44. Absent, the script silently
        # falls back to the dispatcher that may do nothing.
        wlopm
        # Screenshots (satty comes from the mineiro/satty copr enabled above,
        # not from Fedora proper)
        satty grim slurp grimblast
        # Tools
        bc jq curl git lm_sensors unzip socat
        # Found by scripts/check-deps.sh, all four invoked at runtime and
        # none of them declared until now. They were present on the older
        # machines as transitive deps of something else, which is why the
        # gap stayed invisible until a Minimal Install had none of them.
        #
        # dbus-tools -> dbus-update-activation-environment, the FIRST line of
        #   hypr/hyprland.lua's autostart. It pushes WAYLAND_DISPLAY and
        #   XDG_CURRENT_DESKTOP into the DBus/systemd activation environment;
        #   without it the XDG portals come up with an empty environment and
        #   screen sharing and the GTK file picker fail. The failure is
        #   remote from its cause: nothing along the way says "dbus-tools".
        # pulseaudio-utils -> pactl, used by quickshell/bar/modules/
        #   AudioOutput.qml (the bar's whole audio module),
        #   hypr/scripts/restore-mic-port.sh (autostarted) and
        #   wireplumber/systemd/bt-audio-switch.sh. This is NOT PulseAudio
        #   the server -- pipewire-pulseaudio above provides that. pactl is
        #   only the CLI, and it ships in its own package.
        # inotify-tools -> inotifywait, the event loop of
        #   hypr/scripts/wallpaper-cache-watcher.sh, also autostarted.
        #   Absent, the watcher exits at once and the wallpaper thumbnail
        #   cache silently stops updating.
        # libnotify -> notify-send, used by power-profile.sh,
        #   display-layout.sh and dashboard-toggle.sh. The mildest of the
        #   four: every call site already tolerates its absence, so it only
        #   costs the toasts.
        dbus-tools pulseaudio-utils inotify-tools libnotify
        # edid-decode, pour la detection de capacite HDR de waybar/scripts/
        # hdr.sh. Le seul des cinq qui degrade proprement : chaque appel est
        # garde par `command -v` et son absence fait traiter l'ecran comme
        # capable plutot que de bloquer (voir le commentaire du script). Il
        # entre quand meme dans la liste -- une detection qui repond "oui"
        # faute d'outil n'est pas une detection.
        v4l-utils
        # hypr/scripts/bar-tint.py's two hard imports. It samples the top
        # strip of the wallpaper and writes ~/.cache/bar-tint.json, which
        # quickshell/bar/services/BandTint.qml watches -- that file is the
        # ONLY thing telling the bar whether to draw light or dark ink, and
        # the band is 55% transparent (#730c0c0e), so getting it wrong leaves
        # white ink on a light wallpaper, under WCAG AA.
        #
        # Both are load-bearing, not optional niceties: numpy does the sRGB
        # linearisation and the per-bucket means, PIL does the load/resize/
        # crop. There is no degraded mode without them -- the script dies on
        # the import, before main() is ever reached.
        #
        # Never listed before because the two machines this repo grew on both
        # had them pulled in by something else; a Fedora "Minimal Install" has
        # neither, and the failure left no trace at all until the bar-tint.log
        # redirect in scripts/set_wallpaper.sh (see its comment).
        python3-numpy python3-pillow
        # Qt theming
        qt5ct qt6ct
        # Qt5Compat.GraphicalEffects -- imported by quickshell/bar/modules/
        # balise/BaliseHome.qml. Without it quickshell exits immediately at
        # startup ("module Qt5Compat.GraphicalEffects is not installed") and
        # there is simply no bar. It used to arrive as a transitive dep of the
        # kde module, so a machine that skips KDE (or a Fedora "Minimal
        # Install") never got it.
        qt6-qt5compat
        # Balise build deps (the Rust daemon + its legacy GTK window) --
        # no Fedora package, built from source further down in this script.
        # Named Orbit here until Balise replaced it.
        rust cargo gtk4-devel gtk4-layer-shell-devel NetworkManager-libnm-devel bluez-libs-devel
    )

elif [ "$DISTRO" = "arch" ]; then
    PKGS=(
        # Hyprland ecosystem
        dbus hyprland hyprlock hypridle xdg-desktop-portal-hyprland xdg-desktop-portal-gtk
        # Bar / notifications / launcher
        # quickshell is the active bar AND the active notification daemon
        # (see quickshell/bar/services/NotificationState.qml); waybar
        # stays installed as a fallback, not started. No separate
        # notification daemon package needed any more (used to be
        # swaync, before that dunst).
        quickshell waybar rofi-wayland khal hyprsunset
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
        # bar-tint.py's imports -- see the Fedora list for why these are
        # mandatory rather than nice-to-have.
        python-numpy python-pillow
        # Qt
        qt5ct qt6ct
        # Qt5Compat.GraphicalEffects, imported by quickshell/bar/modules/
        # balise/BaliseHome.qml -- quickshell won't start without it.
        qt6-5compat
        # NOTE: Hyprland also wants hyprland-qtutils (renamed hyprland-guiutils
        # upstream) for its dialogs. Left out deliberately: pacman runs without
        # a --skip-unavailable equivalent here, so a wrong name would abort the
        # whole transaction. Add it once the current Arch name is confirmed.
        # NOTE: idle-action.sh's dpms-off prefers wlopm (see the Fedora list).
        # Not added here: on Arch it lives in the AUR, which pacman does not
        # read, and an unknown name aborts the whole transaction. The script
        # already degrades to the Hyprland dispatcher without it.
        # Balise build deps
        rust cargo gtk4-layer-shell libnm bluez-libs
    )

elif [ "$DISTRO" = "debian" ]; then
    warn "Debian/Ubuntu: hyprland, swww and hyprlock may need manual install."
    warn "quickshell (the active bar AND notification daemon, see quickshell/bar/) is not packaged in apt — build from source (https://quickshell.org/docs/v0.3.0/guide/install-setup/) or install manually. waybar is still installed below as a fallback, just not started."
    warn "Balise build deps (rust/cargo, libgtk4-layer-shell-dev, libnm-dev, libbluetooth-dev) vary a lot across Debian/Ubuntu versions — install manually if the cargo build step below fails."
    warn "xcursorgen ships in the x11-apps meta-package on Debian/Ubuntu (pulls in xeyes/xclock etc. as a side effect) — install it standalone if you'd rather avoid that."
    PKGS=(
        dbus dbus-x11 hyprland
        waybar rofi khal hyprsunset
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
        # bar-tint.py's imports -- see the Fedora list for why these are
        # mandatory rather than nice-to-have. Pillow is python3-pil here.
        python3-numpy python3-pil
        qt5ct
        # Qt5Compat.GraphicalEffects for quickshell's bar (see the Fedora list).
        # Only useful once quickshell itself is built from source, per the warn
        # above, but harmless to pull in early.
        qml6-module-qt5compat-graphicaleffects
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
#
# What this binary is FOR, now that the UI has moved: `balise daemon` is
# the backend -- NetworkManager/BlueZ logic behind a Unix socket -- and
# that is what the session runs (systemd/balise.service). The panel the
# user sees is QML, in quickshell/bar/modules/balise/, talking to that
# socket. The crate's own GTK4 window (`balise toggle`) still builds and
# still works, but nothing opens it any more; config/hyprland/balise/'s
# config.toml and style.css theme THAT window, so they are legacy too
# (the QML panel is styled from quickshell/bar/theme/). Still symlinked
# further down with the other module directories.
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
# Same logic as the Balise/Prisme blocks above: source vendored in this repo
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
        # THEMENAME has to reach make too, not just build-cursors. A
        # `VAR=x cmd1 && cmd2` prefix scopes the variable to cmd1 ALONE, so
        # the previous one-liner built build/White.theme and then ran a make
        # that fell back to the upstream default (`THEMENAME ?= Custom` in
        # the Makefile): install went looking for build/Custom.theme, died on
        # it, and left a half-written ~/.icons/ComixCursors-Custom with 30
        # cursors and no index.theme. Passed on the command line rather than
        # exported, so it also beats an inherited THEMENAME.
        if (cd "$COMIX_BUILD" \
            && MULTISIZE=true THEMENAME="$COMIX_THEME_NAME" ./bin/build-cursors \
            && make THEMENAME="$COMIX_THEME_NAME" \
            && make install THEMENAME="$COMIX_THEME_NAME"); then
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
# LUCIDE ICONS (quickshell bar icons -- Fonts.qml's iconLucide)
# ============================================================
# ISC-licensed (verified via its own LICENSE file), not packaged by any
# distro -- pulled from the `lucide-static` npm package, which is the
# only official channel shipping Lucide as a real icon FONT rather than
# per-icon SVGs. ONE file, one family ("lucide"), 2118 glyphs: unlike
# Phosphor above there is no per-weight family to loop over, because
# Lucide has no weights at all (see Fonts.qml's own LUCIDE TEST note for
# what that costs the bar). Copied flat into ~/.local/share/fonts,
# alongside Phosphor -- both stay installed so Fonts.qml's `lucideTest`
# can be flipped either way without reinstalling anything.
section "Checking Lucide Icons font"

if fc-list | grep -qi "lucide"; then
    ok "Lucide Icons already installed."
elif ! command -v curl &>/dev/null || ! command -v jq &>/dev/null; then
    warn "curl/jq not available. Install Lucide Icons manually:"
    warn "https://github.com/lucide-icons/lucide"
else
    info "Downloading Lucide Icons (lucide-static, latest)..."
    LUCIDE_TMP="$(mktemp -d)"
    # `|| true`: same reasoning as the Phosphor block above -- a bare
    # failing assignment outside an if/&&/|| would take the whole script
    # down via `set -e`, and this download is best-effort.
    LUCIDE_VERSION="$(curl -fsL https://registry.npmjs.org/lucide-static \
        | jq -r '."dist-tags".latest' 2>/dev/null)" || true

    if [ -n "$LUCIDE_VERSION" ] && [ "$LUCIDE_VERSION" != "null" ] \
        && curl -fLo "$LUCIDE_TMP/lucide.tgz" \
            "https://registry.npmjs.org/lucide-static/-/lucide-static-${LUCIDE_VERSION}.tgz" \
        && tar -xzf "$LUCIDE_TMP/lucide.tgz" -C "$LUCIDE_TMP" package/font/lucide.ttf; then
        mkdir -p ~/.local/share/fonts
        cp "$LUCIDE_TMP/package/font/lucide.ttf" ~/.local/share/fonts/
        fc-cache -f ~/.local/share/fonts
        ok "Lucide Icons ($LUCIDE_VERSION) installed."
    else
        warn "Lucide Icons download failed. Install manually: https://github.com/lucide-icons/lucide"
    fi
    rm -rf "$LUCIDE_TMP"
fi

# ============================================================
# SYMLINK CONFIG
# ============================================================

if [ "$RESET_MODE" = true ]; then
    warn "Reset mode enabled — removing old configs from $CONFIG"
    rm -rf "$CONFIG"/{hypr,waybar,quickshell,rofi,balise,prisme,roue,hyprlock,scripts,khal}
    ok "Old configs removed"
fi

section "Linking configuration directories"

# Config directories to fully symlink into ~/.config
modules=("hypr" "waybar" "quickshell" "rofi" "balise" "prisme" "roue" "hyprlock" "scripts" "khal" "theme")

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
