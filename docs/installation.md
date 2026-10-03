# Installation

coucou-shell runs on **Fedora 44, x86_64**. A netinstall ("Fedora Everything") with nothing selected is plenty. You'll also need a user account that can use `sudo`.

## Install

```bash
sudo dnf config-manager addrepo --from-repofile=https://lucasssoh.github.io/dotfiles/coucou-shell.repo
sudo dnf install cc-pkg-mng
cc-pkg-mng init
```

The first line adds coucou-shell's package repository. dnf will ask you once whether to trust its signing key.

Run `init` as yourself, not as root. It asks for your password when it needs it, and only once.

When it's done, log out, log back in and pick the Hyprland session. If you installed the login screen, just reboot.

## What `init` asks

All the questions come first. Once you've answered them, the install runs to the end without stopping.

| Question | Default |
|---|---|
| Where to put coucou-shell | `~/coucou-shell`. If there's already a coucou-shell checkout there, it's used as is |
| Channel | **stable**, which follows releases. **edge** follows every commit (see [channels](cc-pkg-mng.md#channels)) |
| The login screen (greetd + tuigreet) | no |
| The boot splash | no |
| Applications | WezTerm, Firefox, Nemo, Neovim and mpv. Brave, MangoHud, fastfetch, ccnote and ccslide are also on offer |
| WezTerm build | `stable`, the packaged one. `smear` builds it from source with a cursor smear effect |
| Each personal setup (shell, WezTerm, Neovim, extras) | keep your own. If you take one, every file it replaces is backed up first |

Before touching anything, `init` shows you the full plan: packages, links, services, and what each step does. Nothing happens until you say yes.

The core of coucou-shell is always installed: Hyprland, the bar, Roue, Prisme, Balise, Manette, Liseuse, the fonts and the theme. The [units](modules.md) page describes each part.

## Unattended install

You can give `init` all its answers in a file:

```bash
cc-pkg-mng init --answers answers.toml
```

```toml
dir     = "~/coucou-shell"
channel = "stable"
# Optional parts, applications and personal setups to install.
# The core is always installed.
units   = ["plymouth", "wezterm", "firefox", "nemo", "neovim", "mpv", "config-shell"]

[answers.wezterm]
variant = "stable"
```

Anything you leave out gets its default. If you're happy with every default, `cc-pkg-mng init --yes` skips the file altogether.

## After the install

Check your screens' names, and edit [`monitors.lua`](../config/hyprland/hypr/monitors.lua) if they don't match. `hyprctl reload` (or `Super + Shift + R`) applies the change.

```bash
hyprctl monitors
```

Drivers for your CPU and GPU are installed along with everything else. If something has to be done by hand, you'll see it listed at the end of the run. [hardware.md](hardware.md) has the details.

`cc-pkg-mng status` tells you what's installed and whether it's all in place. For keeping things up to date, see [cc-pkg-mng.md](cc-pkg-mng.md).

## Coming from an earlier setup

If this machine already has a checkout of these dotfiles, point `init` at it. It picks up the checkout and whatever the old manager had installed, then only does what's missing.

```bash
cc-pkg-mng init --dir ~/code/dotfiles
```
