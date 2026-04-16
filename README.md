# Dotfiles

## Installation

1. Cloner le dépôt :
```bash
git clone https://github.com/lucasssoh/dotfiles.git
cd dotfiles
```

2. Rendre les scripts exécutables :
```bash
chmod +x setup_fedora.sh install_all.sh
```

3. Préparer le système (Fedora) :
```bash
./setup_fedora.sh
```

4. Déployer les configurations :
```bash
./install_all.sh
```

## Contenu des scripts

* **setup_fedora.sh** : Mise à jour du système, installation des drivers (Mesa/Vulkan), de la stack audio (Pipewire), du Bluetooth et des services de base.
* **install_all.sh** : Installation modulaire des polices, de Tmux, de Wezterm, de Neovim et de l'environnement graphique Hyprland.
