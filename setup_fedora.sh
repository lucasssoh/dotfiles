#!/usr/bin/env bash
set -e

echo "[INFO] Mise à jour système..."
sudo dnf upgrade -y

# =========================
# BASE SYSTEM (indispensable)
# =========================
echo "[INFO] Base system..."
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
# RESEAU (wifi + ethernet)
# =========================
echo "[INFO] Réseau..."
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
echo "[INFO] Bluetooth..."
sudo dnf install -y \
    bluez

# =========================
# AUDIO (stack moderne)
# =========================
echo "[INFO] Audio..."
sudo dnf install -y \
    pipewire \
    pipewire-pulse \
    pipewire-alsa \
    wireplumber \
    alsa-utils

# =========================
# GPU / RENDERING (headless ready)
# =========================
echo "[INFO] Graphique (base)..."
sudo dnf install -y \
    mesa-dri-drivers \
    mesa-vulkan-drivers \
    vulkan-loader

# =========================
# INPUT DEVICES
# =========================
echo "[INFO] Input..."
sudo dnf install -y \
    libinput \
    xkeyboard-config

# =========================
# STOCKAGE (USB / FS standards)
# =========================
echo "[INFO] Stockage..."
sudo dnf install -y \
    udisks2 \
    ntfs-3g \
    exfatprogs \
    dosfstools

# =========================
# SYSTEM SERVICES / DBUS
# =========================
echo "[INFO] Services système..."
sudo dnf install -y \
    dbus \
    dbus-broker \
    polkit

# =========================
# STANDARDS FREEDESKTOP (neutre)
# =========================
echo "[INFO] Standards..."
sudo dnf install -y \
    xdg-utils \
    xdg-user-dirs

# =========================
# GRAPHICAL LIBS (runtime minimal)
# =========================
echo "[INFO] Librairies graphiques de base..."
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
# UTILITAIRES ESSENTIELS
# =========================
echo "[INFO] Utilitaires..."
sudo dnf install -y \
    tar \
    gzip \
    unzip \
    zip \
    curl \
    wget \
    git \
    rsync \
    nano

# =========================
# ACTIVATION SERVICES
# =========================
echo "[INFO] Activation services..."
sudo systemctl enable --now NetworkManager
sudo systemctl enable --now bluetooth
sudo systemctl enable --now dbus-broker

echo "[OK] Base système Fedora prête ✔"