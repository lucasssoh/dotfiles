#!/bin/bash

echo "[..] Début de l'installation de l'environnement Bash..."

# 1. Mise à jour et installation des paquets système (Fedora)
sudo dnf update -y
sudo dnf install -y fzf zoxide git curl

# 2. Installation de Starship (Le prompt élégant et rapide)
if ! command -v starship &> /dev/null; then
    echo "[..] Installation de Starship..."
    curl -sS https://starship.rs/install.sh | sh -s -- -y
fi

# 3. Création des liens symboliques
# On sauvegarde l'ancien bashrc s'il existe
[ -f ~/.bashrc ] && mv ~/.bashrc ~/.bashrc.bak

ln -sf $(pwd)/.bashrc ~/.bashrc
ln -sf $(pwd)/.bash_aliases ~/.bash_aliases

echo "[OK] Installation terminée ! Relance ton terminal ou tape 'source ~/.bashrc'"
