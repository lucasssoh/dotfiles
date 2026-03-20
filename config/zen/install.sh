#!/usr/bin/env bash
set -e

# 1. S'assurer que Flatpak est installé et que Flathub est activé
echo "[INFO] Vérification de Flatpak..."
if command -v dnf &> /dev/null; then
    sudo dnf install -y flatpak
elif command -v pacman &> /dev/null; then
    sudo pacman -S --noconfirm flatpak
elif command -v apt-get &> /dev/null; then
    sudo apt-get update && sudo apt-get install -y flatpak
fi

# Ajouter le dépôt Flathub s'il n'existe pas
sudo flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo

# 2. Installation de Zen Browser
echo "[INFO] Installation de Zen Browser via Flatpak..."
# On utilise l'ID de l'application sur Flathub
sudo flatpak install -y flathub io.github.zen_browser.zen

# 3. Intégration (Ta philosophie)
# Optionnel : Créer un alias pour le lancer plus vite dans le terminal
DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# Symlinks pour lancer zen depuis le terminal et Hyprland
sudo ln -sf /var/lib/flatpak/exports/bin/app.zen_browser.zen /usr/local/bin/zen
sudo ln -sf /var/lib/flatpak/exports/bin/app.zen_browser.zen /usr/local/bin/zen-browser

echo "[OK] Zen Browser (Flatpak) installé."