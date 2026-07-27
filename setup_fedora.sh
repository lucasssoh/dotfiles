#!/usr/bin/env bash
set -e

BOLD="\e[1m"
GREEN="\e[32m"
YELLOW="\e[33m"
BLUE="\e[34m"
RESET="\e[0m"

info() { echo -e "${BLUE}[INFO]${RESET}  $*"; }
ok()   { echo -e "${GREEN}[ OK ]${RESET}  $*"; }
warn() { echo -e "${YELLOW}[WARN]${RESET}  $*"; }

info "Updating system..."
sudo dnf upgrade -y
# =========================
# BASE SYSTEM (essential)
# =========================
info "Base system..."
sudo dnf install -y \
    bash \
    coreutils \
    util-linux \
    findutils \
    grep \
    sed \
    gawk \
    less \
    which \
    file
# =========================
# NETWORK (wifi + ethernet)
# =========================
info "Network..."
sudo dnf install -y \
    NetworkManager \
    NetworkManager-tui \
    wpa_supplicant \
    iproute \
    iputils \
    dhcp-client

# =========================
# BLUETOOTH
# =========================
info "Bluetooth..."
sudo dnf install -y \
    bluez

# bluetuith — Bluetooth TUI via copr
info "Installing bluetuith via copr..."
sudo dnf copr enable -y lxdes/bluetuith
sudo dnf install -y bluetuith
ok "bluetuith installed."

# =========================
# AUDIO (modern stack)
# =========================
info "Audio..."
sudo dnf install -y \
    pipewire \
    pipewire-pulse \
    pipewire-alsa \
    wireplumber \
    alsa-utils
# =========================
# GPU / RENDERING (headless ready)
# =========================
info "Graphics (base)..."
sudo dnf install -y \
    mesa-dri-drivers \
    mesa-vulkan-drivers \
    vulkan-loader
# =========================
# INPUT DEVICES
# =========================
info "Input..."
sudo dnf install -y \
    libinput \
    xkeyboard-config
# =========================
# STORAGE (USB / standard filesystems)
# =========================
info "Storage..."
sudo dnf install -y \
    udisks2 \
    ntfs-3g \
    exfatprogs \
    dosfstools
# =========================
# SYSTEM SERVICES / DBUS
# =========================
info "System services..."
sudo dnf install -y \
    dbus \
    dbus-broker \
    polkit
# =========================
# FREEDESKTOP STANDARDS (neutral)
# =========================
info "Standards..."
sudo dnf install -y \
    xdg-utils \
    xdg-user-dirs
# =========================
# GRAPHICAL LIBS (runtime minimal)
# =========================
info "Base graphical libraries..."
sudo dnf install -y \
    xorg-x11-server-Xwayland \
    gtk3 \
    gtk4 \
    qt5-qtbase \
    qt6-qtbase \
    libX11 \
    libXcursor \
    libXrandr \
    libXi \
    libXext \
    libXrender
# =========================
# ESSENTIAL UTILITIES
# =========================
info "Utilities..."
sudo dnf install -y \
    tar \
    gzip \
    unzip \
    zip \
    curl \
    wget \
    git \
    rsync \
    nano \
    snapd
# Enable the snapd socket
sudo systemctl enable --now snapd.socket
# Create the classic /snap symlink if needed
if [ ! -e /snap ]; then
    sudo ln -s /var/lib/snapd/snap /snap
fi
# Wait for snap to be ready
info "Waiting for snapd to be operational..."
sleep 5
# Install snaps (example: pulsemixer)
sudo snap install pulsemixer --classic || warn "pulsemixer could not be installed for now."
# =========================
# ENABLE SERVICES
# =========================
info "Enabling services..."
sudo systemctl enable --now NetworkManager
sudo systemctl enable --now bluetooth
sudo systemctl enable --now dbus-broker

sudo loginctl enable-linger "$USER"
ok "Base Fedora system ready."
