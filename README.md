# Dotfiles

## Installation

1. Clone the repo:
```bash
git clone https://github.com/lucasssoh/dotfiles.git
cd dotfiles
```

2. Make the scripts executable:
```bash
chmod +x setup_fedora.sh install_all.sh
```

3. Prepare the system (Fedora):
```bash
./setup_fedora.sh
```

4. Deploy the configurations:
```bash
./install_all.sh
```

## What the scripts do

* **setup_fedora.sh**: System update, driver install (Mesa/Vulkan), audio stack (Pipewire), Bluetooth, and base services.
* **install_all.sh**: Modular install of fonts, Tmux, WezTerm, Neovim, and the Hyprland graphical environment.
