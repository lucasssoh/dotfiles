# Installation

coucou-shell needs **Fedora 44, x86_64** — a netinstall ("Fedora Everything") with nothing selected is enough — and a user with `sudo`.

## Install

```bash
sudo dnf config-manager addrepo --from-repofile=https://lucasssoh.github.io/dotfiles/coucou-shell.repo
sudo dnf install cc-pkg-mng
cc-pkg-mng init
```

The first line adds coucou-shell's package repository; dnf asks once to trust its signing key. Run `init` as your user, not as root: it asks for your password once, when it needs it.

Then log out and back in, and pick the Hyprland session (or reboot, with the login screen).

## What `init` asks

Everything is asked up front; the install then runs without stopping.

| Question | Default |
|---|---|
| Where to put coucou-shell | `~/coucou-shell`. An existing coucou-shell checkout is used as it is |
| Channel | **stable**, the latest release. **edge** follows every commit — see [channels](cc-pkg-mng.md#channels) |
| The login screen (greetd + tuigreet) | no |
| The boot splash | no |
| Applications | WezTerm, Firefox, Nemo, Neovim, mpv. Also offered: Brave, MangoHud, fastfetch, ccnote, ccslide |
| WezTerm build | `stable`, the packaged build. `smear` builds it from source with a cursor smear |
| Each configuration (shell, WezTerm, Neovim, extras) | keep yours. Taking one backs up every file it replaces |

Before changing anything, `init` shows the plan: packages, links, services, and what each step does. Nothing happens until you confirm.

The core of coucou-shell — Hyprland, the bar, Roue, Prisme, Balise, Liseuse, fonts and theme — is always installed. See [units](modules.md) for what each part contains.

## Unattended install

Every answer can come from a file:

```bash
cc-pkg-mng init --answers answers.toml
```

```toml
dir     = "~/coucou-shell"
channel = "stable"
# Optional parts, applications and configurations to take;
# the core is always installed.
units   = ["plymouth", "wezterm", "firefox", "nemo", "neovim", "mpv", "config-shell"]

[answers.wezterm]
variant = "stable"
```

A key left out takes its default. `cc-pkg-mng init --yes` takes every default without a file.

## After the install

Check the screen names and adjust [`monitors.lua`](../config/hyprland/hypr/monitors.lua) if needed; `hyprctl reload` (`Super + Shift + R`) applies it:

```bash
hyprctl monitors
```

Drivers for the detected CPU and GPU are installed with the rest; anything that has to be done by hand is printed at the end — see [hardware.md](hardware.md).

`cc-pkg-mng status` shows what is installed and whether it is in place. To keep up to date, see [cc-pkg-mng.md](cc-pkg-mng.md).

## Coming from an earlier setup

If this machine already has a checkout of these dotfiles, point `init` at it; it picks up the checkout and what the previous manager had installed, and only does what is missing:

```bash
cc-pkg-mng init --dir ~/code/dotfiles
```
