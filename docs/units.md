# Units

coucou-shell is installed as **units**, in three layers:

- the **core**, always installed. Only the login screen, the boot splash and Programme are optional;
- **applications**, the ones picked at install;
- **configurations**, the author's setups, adopted or not.

`cc-pkg-mng info <unit>` shows what a unit installs, links and runs. To install or remove one, see [cc-pkg-mng](cc-pkg-mng.md).

## Core

| Unit | What it brings | Guide |
|---|---|---|
| `base` | The Fedora foundation: shell utilities, NetworkManager, Bluetooth, PipeWire, Mesa and Vulkan, storage (NTFS and exFAT), D-Bus and polkit, the GTK and Qt libraries, snapd. On a fresh machine, it upgrades the system first | |
| `hardware` | Drivers and tools for the CPU and GPU, and hardware video decoding | [Hardware](hardware.md) |
| `fonts` | The interface, terminal and icon fonts | [Theme and fonts](session/theme.md#fonts) |
| `theme` | GTK colours, icons, cursor, Qt settings | [Theme and fonts](session/theme.md) |
| `audio` | The equalizer's chains and the Bluetooth audio policy | [Audio](session/audio.md) |
| `hyprland` | The compositor, lock, idle, night mode, portals, wallpapers | [Hyprland](session/hyprland.md), [displays](session/displays.md), [wallpapers](session/wallpapers.md), [lock screen](session/lock.md) |
| `roles` | What `Super + Enter`, `Super + B` and `Super + E` open | [Default applications](session/hyprland.md#default-applications) |
| `bar` | The bar and its drawers, notifications, Veille, the screenshot tools, the clipboard history, the font viewer | [The bar](bar/index.md), [Screenshot](tools/screenshot.md), [font viewer](tools/fontview.md) |
| `pouls` | The bar's figures, the charger and the charge policy | [Metrics](bar/metrics.md), [power](bar/power.md) |
| `balise` | Wi-Fi, Bluetooth and Ethernet behind the bar | [Balise](bar/balise.md) |
| `roue` | The radial wheels | [Roue](tools/roue.md) |
| `prisme` | The wallpaper picker | [Prisme](tools/prisme.md) |
| `manette` | Game controllers and their menu | [Manette](tools/manette.md) |
| `sesame` | Password prompts | [Sésame](tools/sesame.md) |
| `fuzzel` | The launcher and the clipboard list | [Launcher](tools/launcher.md) |
| `liseuse` | The reading library | [Liseuse](tools/liseuse.md) |
| `programme` | *Optional.* The study agenda | [Programme](bar/programme.md) |
| `plymouth` | *Optional.* The boot splash | [Boot splash](session/boot-splash.md) |
| `greeter` | *Optional.* The login screen | [Login screen](session/login.md) |

## Applications

Each is the application alone. To use another instead, install it, then make it the [default for its role](session/hyprland.md#default-applications).

| Unit | What it is | By default | Guide |
|---|---|---|---|
| `wezterm` | The terminal | yes | [WezTerm](apps/wezterm.md) |
| `firefox` | The web browser | yes | [Firefox](apps/firefox.md) |
| `nemo` | The file manager | yes | [Nemo](apps/nemo.md) |
| `neovim` | The editor | yes | [Neovim](apps/neovim.md) |
| `mpv` | The video and music player | yes | [mpv](apps/mpv.md) |
| `swayimg` | The image viewer | yes | [swayimg](apps/swayimg.md) |
| `games` | Steam and Lutris | no | [Games](apps/games.md) |
| `brave`, `mangohud`, `fastfetch`, `ccnote`, `ccslide` | Smaller extras | no | [Extras](apps/extras.md#applications) |

## Configurations

| Unit | What it is | Guide |
|---|---|---|
| `config-shell` | zsh and bash, prompt, aliases, tmux | [Extras](apps/extras.md#config-shell) |
| `config-wezterm` | The author's WezTerm setup | [WezTerm](apps/wezterm.md#authors-setup) |
| `config-nvim` | The author's Neovim setup | [Neovim](apps/neovim.md#authors-setup) |
| `config-extras` | Settings for mpv, MangoHud, fastfetch and Brave | [Extras](apps/extras.md#config-extras) |

To write one, see [writing a unit](writing-a-unit.md).
