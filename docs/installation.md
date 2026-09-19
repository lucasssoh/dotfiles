# Installation

## First install

```bash
git clone https://github.com/lucasssoh/dotfiles.git
cd dotfiles
./install
```

`./install` is for a bare clone, where nothing is on `PATH` yet. It translates its arguments and delegates to [`bin/cc-pkg-mng`](../bin/cc-pkg-mng). Once the `ccpkg` module has run, `cc-pkg-mng` is available directly and is what you use from then on — see [cc-pkg-mng.md](cc-pkg-mng.md).

| Command | What it installs | sudo |
|---|---|---|
| `./install` | Everything: the system phase, then every module | yes |
| `./install system` | Base Fedora packages and services ([`setup_fedora.sh`](../setup_fedora.sh)), then the hardware drivers this machine needs | yes |
| `./install hardware` | The hardware drivers only | yes |
| `./install user` | Modules, symlinks, Rust binaries — nothing root-owned | no |
| `./install greeter` | greetd + tuigreet, console in JetBrains Mono. Interactive | yes |

| Option | |
|---|---|
| `--dry-run` | Print the ordered list of what would run, change nothing |
| `--detect` | Print the hardware detection and exit |
| `--help` | Usage |

`boot/login` (the `greeter` verb) and `kde` are [opt-in](modules.md#opt-in): never part of a default run.

## What the phases do

**`system`** installs the base package set — network, bluetooth, the pipewire stack, Mesa, input, storage, dbus/polkit, xdg, the GTK/Qt libraries — enables the matching services, then runs the hardware phase.

**`hardware`** detects the CPU and GPU and installs only what *this* machine needs. It is not hardcoded; see [hardware.md](hardware.md).

**`user`** runs every module in registry order, symlinks the repo into `~/.config`, and builds the Rust binaries. Nothing here needs root on a machine whose packages are already present.

## After a fresh install

Re-login, or start Hyprland directly:

```bash
Hyprland
```

Check output names and adjust [`config/hyprland/hypr/monitors.lua`](../config/hyprland/hypr/monitors.lua) if needed — it is symlinked, so changes apply on the next `hyprctl reload`:

```bash
hyprctl monitors
```

Then confirm the machine matches the repo:

```bash
cc-pkg-mng verify --full
```

## Running a single module

Every `config/*/install.sh` remains executable on its own, as do `install_all.sh` and `setup_fedora.sh`:

```bash
bash config/nvim/install.sh
```

A module run this way may install packages and will ask for sudo if something is missing. The same module run through `cc-pkg-mng update` will not.

## Bootstrapping notes

- `./install` must keep working from a clone with nothing else present. That is the only reason the file still exists: all of its logic now lives in `bin/cc-pkg-mng`, which is not yet on `PATH` at that point.
- `cc-pkg-mng` is **symlinked** into `~/.local/bin`, never copied, so a later `git pull` updates the command itself with nothing to rebuild.
- `~/.local/bin` reaches `PATH` through [`config/bash/.bashrc`](../config/bash/.bashrc), installed by the `bash` module — which is why `ccpkg` is ordered right after it.
