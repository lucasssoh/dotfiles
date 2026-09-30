# Dotfiles

A Fedora + [Hyprland](https://hyprland.org/) desktop, installed and kept up to date by its own manager. Besides the configuration of existing tools, it ships three native Rust/GTK4 apps: **[Roue](config/hyprland/roue-src)** (a radial selection wheel), **[Prisme](config/hyprland/prisme-src)** (a wallpaper picker) and **[Balise](config/hyprland/balise-src)** (a WiFi/Bluetooth/Ethernet daemon behind a panel in the bar).

## Quick start

```bash
git clone https://github.com/lucasssoh/dotfiles.git
cd dotfiles
./install
```

Then, to stay up to date:

```bash
cc-pkg-mng update     # pull, then apply only what changed
cc-pkg-mng verify     # check that everything is still in place
```

## Documentation

| Page | Contents |
|---|---|
| [**Installation**](docs/installation.md) | First install, the three phases, running a single module |
| [**cc-pkg-mng**](docs/cc-pkg-mng.md) | Commands, options, privilege scope, exit codes, what `verify` checks |
| [**Configuration**](docs/configuration.md) | State and logs, environment variables, the module registry, adding a module, Rust crates |
| [**Modules**](docs/modules.md) | What each module installs, and where to configure it |
| [**Hardware detection**](docs/hardware.md) | CPU/GPU profiles, codec swaps, manual follow-ups |
| [**Key bindings**](docs/keybindings.md) | The full list, AZERTY |

## What's in here

| Piece | What it is |
|---|---|
| **Hyprland** (`config/hyprland/hypr/`) | Compositor config, in Hyprland's Lua API: `hyprland.lua`, `keybinds.lua`, `windowrules.lua`, `monitors.lua`, plus per-machine profiles in `hosts/` and an optional git-ignored `private.lua` |
| **Quickshell bar** (`config/hyprland/quickshell/bar/`) | The status bar: clock and metrics, workspaces and media, and drawers for network, power, audio mixer with per-app equalizer, notifications and calendar |
| **Veille** (`quickshell/bar/modules/veille/`) | A large clock overlay for late sessions, with occasional messages. Configured in `quickshell/bar/veille.json` |
| **Roue** (`config/hyprland/roue-src/`) | Radial wheel: power menu, power profile, display layout, actions |
| **Prisme** (`config/hyprland/prisme-src/`) | Wallpaper picker, and `wallpaper-filter` to fit wallpapers to each screen |
| **Balise** (`config/hyprland/balise-src/` + `quickshell/bar/modules/balise/`) | Rust daemon for NetworkManager/BlueZ, and the bar panel that drives it. Shares a saved network as a QR code. No VPN |
| **Liseuse** (`config/liseuse/`) | Reading library on `Super + F`: a picker over `~/Livres` and the folders in `sources.conf`, opening PDF, EPUB, comics, Markdown (with maths and PlantUML) in zathura. `liseuse convert` turns office documents into PDFs |
| **cc-pkg-mng** (`bin/cc-pkg-mng`) | The repo's install/update manager: applies only the modules that changed, rebuilds only the Rust crates that need it, and verifies the result |
| **Boot** (`config/boot/`) | Plymouth splash (`boot/plymouth`), and an opt-in greetd + tuigreet login with the console in JetBrains Mono (`boot/login`) |
| Everything else in `config/` | bash/zsh, tmux, wezterm, nvim, pipewire, wireplumber, nemo, fuzzel, fonts, mpv, mangohud, fastfetch, firefox, brave — plus KDE as an opt-in session. See [docs/modules.md](docs/modules.md) |

## Licence

coucou-shell is for personal use: install it, use it and adapt it on your own machines, but don't redistribute it — see [LICENSE](LICENSE). Third-party parts keep their own licences, listed in [THIRD-PARTY.md](THIRD-PARTY.md).

## Monitors & HDR

After the first launch, check output names with `hyprctl monitors` and adjust `config/hyprland/hypr/monitors.lua` if needed; `hyprctl reload` applies it. HDR is toggled per screen from the Balise drawer.
