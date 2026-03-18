#!/usr/bin/env bash
set -e

echo "[INFO] Mise à jour du système..."
sudo dnf copr enable solopasha/hyprland
sudo dnf update -y

echo "[INFO] Installation des services de base..."
sudo dnf install -y \
    NetworkManager \
    bluetooth \
    bluez \
    bluez-tools \
    pipewire \
    pipewire-pulse \
    wireplumber \
    xdg-desktop-portal \
    xdg-desktop-portal-hyprland \
    polkit \
    htop \
    unzip \
    curl \
    git \
    wget \
    tar \
    xdg-utils

echo "[INFO] Activation des services essentiels..."
sudo systemctl enable --now NetworkManager
sudo systemctl enable --now bluetooth

echo "[OK] Fedora prête avec les services et utilitaires de base !"