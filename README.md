# coucou-shell

<p align="center">
  <a href="#install"><img alt="Install: 3 commands" src="https://img.shields.io/badge/Install-3%20commands-0A84FF?style=for-the-badge&labelColor=555555&color=0A84FF"></a>
  <a href="https://fedoraproject.org/"><img alt="Fedora: 44 · 45" src="https://img.shields.io/badge/Fedora-44%20%C2%B7%2045-51A2DA?style=for-the-badge&labelColor=555555&color=51A2DA"></a>
  <a href="https://github.com/lucasssoh/dotfiles/releases/latest"><img alt="Release" src="https://img.shields.io/github/v/release/lucasssoh/dotfiles?style=for-the-badge&amp;label=release&amp;labelColor=555555&amp;color=30A46C"></a>
  <a href="https://lucasssoh.github.io/dotfiles/"><img alt="Docs: website" src="https://img.shields.io/badge/Docs-website-E5484D?style=for-the-badge&labelColor=555555&color=E5484D"></a>
  <a href="LICENSE"><img alt="License: GPL-3.0" src="https://img.shields.io/badge/License-GPL--3.0-D4A017?style=for-the-badge&labelColor=555555&color=D4A017"></a>
</p>
<p align="center">
  <a href="https://hypr.land/"><img alt="Hyprland: 0.57" src="https://img.shields.io/badge/Hyprland-0.57-00A8C6?style=flat&labelColor=555555&color=00A8C6&logo=hyprland&logoColor=white"></a>
  <a href="https://www.rust-lang.org/"><img alt="Rust: 9 crates" src="https://img.shields.io/badge/Rust-9%20crates-CE422B?style=flat&labelColor=555555&color=CE422B&logo=rust&logoColor=white"></a>
  <a href="https://quickshell.org/"><img alt="Quickshell: the bar" src="https://img.shields.io/badge/Quickshell-the%20bar-8E4EC6?style=flat&labelColor=555555&color=8E4EC6"></a>
  <a href="https://www.gtk.org/"><img alt="GTK: 4" src="https://img.shields.io/badge/GTK-4-4E9A06?style=flat&labelColor=555555&color=4E9A06&logo=gtk&logoColor=white"></a>
  <a href="https://mpv.io/"><img alt="mpv: Antenne" src="https://img.shields.io/badge/mpv-Antenne-691F69?style=flat&labelColor=555555&color=691F69&logo=mpv&logoColor=white"></a>
  <a href="https://pipewire.org/"><img alt="PipeWire: EQ per app" src="https://img.shields.io/badge/PipeWire-EQ%20per%20app-3A6EA5?style=flat&labelColor=555555&color=3A6EA5"></a>
</p>

A desktop built on [Hyprland](https://hyprland.org/) and [Quickshell](https://quickshell.org/), with its own bar, its own tools, and a manager that installs it and keeps it up to date.

<picture><source media="(prefers-color-scheme: dark)" srcset="docs/screenshots/showcase-dark.webp"><img src="docs/screenshots/showcase.webp" alt="Two screens: the controller menu, and the calendar with Balise"></picture>

**Documentation and video: https://lucasssoh.github.io/dotfiles/**

## Install

On Fedora 44 or 45. A minimal netinstall is enough.

```bash
sudo dnf config-manager addrepo --from-repofile=https://lucasssoh.github.io/dotfiles/coucou-shell.repo
sudo dnf install cc-pkg-mng
cc-pkg-mng init
```

Then, day to day:

```bash
cc-pkg-mng upgrade    # move to the latest release and apply it
cc-pkg-mng status     # check that everything is in place
```

## Made for coucou-shell

| Tool | What it does |
|---|---|
| [**The bar**](docs/bar/index.md) | Clock and agenda, the machine's figures, workspaces and music, and a drawer for the network, sound, power and notifications |
| [**Roue**](docs/tools/roue.md) | A radial wheel: press, aim, let go |
| [**Prisme**](docs/tools/prisme.md) | The wallpaper picker, with light and dark pairs |
| [**Balise**](docs/bar/balise.md) | Wi-Fi, Bluetooth, Ethernet and screen settings, from the bar |
| [**Manette**](docs/tools/manette.md) | Your games, on the controller's Guide button |
| [**Antenne**](docs/apps/antenne.md) | Free TV channels with a guide, and the shows you follow |
| [**Sésame**](docs/tools/sesame.md) | One card for every password asked outside a terminal |
| [**Liseuse**](docs/tools/liseuse.md) | A reading library on one key |
| [**cc-pkg-mng**](docs/cc-pkg-mng.md) | Installs the parts you pick, and moves between releases |

![At work: Nautilus, WezTerm with fastfetch, Neovim](docs/screenshots/work-dark.webp)

## Documentation

| Page | What you'll find |
|---|---|
| [**Installation**](docs/installation.md) | Installing with dnf, the questions `init` asks, unattended installs |
| [**cc-pkg-mng**](docs/cc-pkg-mng.md) | Commands, channels, upgrading and rolling back |
| [**Your settings**](docs/configuration.md) | Where each setting lives, and how to keep a change through an upgrade |
| [**Key bindings**](docs/keybindings.md) | Every shortcut, on an AZERTY keyboard |
| [**Units**](docs/units.md) | Every part of coucou-shell, with its guide |
| [**Hardware**](docs/hardware.md) | CPU and GPU profiles, codecs, what's left for you to do by hand |
| [**Changelog**](CHANGELOG.md) | What changed in each release |

## Licences

coucou-shell is free software, under the [GPL-3.0](LICENSE) or any later version. You can use, change and share it, as long as what you share stays under the same licence and keeps its credits. The coucou wallpapers and the coucou bird are under [CC BY-SA 4.0](LICENSES/CC-BY-SA-4.0.txt).

Forks are welcome, under a name of their own.

What isn't mine keeps its own licence:

| Material | Licence | Details |
|---|---|---|
| Balise's network logic, adapted from Orbit | MIT | [THIRD-PARTY.md](THIRD-PARTY.md) |
| MingCute icons, in Roue | Apache 2.0 | [THIRD-PARTY.md](THIRD-PARTY.md) |
| Console font, from JetBrains Mono | SIL OFL 1.1 | [THIRD-PARTY.md](THIRD-PARTY.md) |
| Heroic and Lutris logos | CC0 1.0; trademarks of their owners | [THIRD-PARTY.md](THIRD-PARTY.md) |
| GNOME wallpapers | CC BY-SA 3.0 US | [wallpapers/CREDITS.md](wallpapers/CREDITS.md) |
| Films in Antenne's screenshots: Big Buck Bunny, Caminandes and the other Blender Foundation open movies | CC BY 3.0 and 4.0, © Blender Foundation | [blender.org](https://studio.blender.org/films/) |
| Wallpaper of the presentation video: Pepper&Carrot, David Revoy | CC BY 4.0 | [peppercarrot.com](https://www.peppercarrot.com/) |
| Music of the presentation video: "Sunday Smooth", Scott Buckley | CC BY 4.0 | [scottbuckley.com.au](https://www.scottbuckley.com.au/library/sunday-smooth/) |

Fonts, icon fonts and packages are downloaded at install and aren't redistributed here.
