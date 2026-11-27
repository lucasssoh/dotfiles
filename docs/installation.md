# Installation

coucou-shell runs on **Fedora 44 or 45, x86_64**. A netinstall ("Fedora Everything") with nothing selected is plenty. The user account needs `sudo`.

## Install

```bash
sudo dnf config-manager addrepo --from-repofile=https://lucasssoh.github.io/dotfiles/coucou-shell.repo
sudo dnf install cc-pkg-mng
cc-pkg-mng init
```

The first line adds coucou-shell's package repository. dnf asks once whether to trust its signing key.

Run `init` as the user, not as root. It asks for the password once.

When it's done, log out, log back in and pick the Hyprland session. With the login screen installed, reboot.

## What `init` asks

The questions come first, then the install runs to the end.

| Question | Default |
|---|---|
| Where to put coucou-shell | `~/coucou-shell`. If there's already a coucou-shell checkout there, it's used as is |
| Channel | **stable**, which follows releases. **edge** follows every commit (see [channels](cc-pkg-mng.md#channels)) |
| The login screen (greetd + tuigreet) | no |
| The boot splash | no |
| Programme, the study agenda | no |
| Applications | WezTerm, Firefox, Nautilus, Neovim, mpv and swayimg. Nemo, Steam and Lutris, Brave, MangoHud, fastfetch, ccnote and ccslide are also on offer |
| WezTerm build | `stable`, the packaged one. `smear` builds it from source with a cursor smear effect |
| Each personal setup (shell, WezTerm, Neovim, extras) | not adopted. A file an adopted setup replaces is backed up first |

`init` then shows its plan (packages, links, services) and waits for a yes.

The core of coucou-shell is always installed: Hyprland, the bar, Roue, Prisme, Balise, Manette, Sésame, Liseuse, the fonts and the theme. The [units](units.md) page lists every part, with its guide.

## Unattended install

`init` can read its answers from a file:

```bash
cc-pkg-mng init --answers answers.toml
```

```toml
dir     = "~/coucou-shell"
channel = "stable"
# Optional parts, applications and personal setups to install.
# The core is always installed.
units   = ["plymouth", "wezterm", "firefox", "nautilus", "neovim", "mpv", "config-shell"]

[answers.wezterm]
variant = "stable"
```

An answer left out gets its default. `cc-pkg-mng init --yes` takes every default, without a file.

## After the install

Every screen comes on at its preferred mode. To place them, scale them or turn one off, see [displays](session/displays.md).

Hold `Super` to see the [key bindings](keybindings.md). To change something, see [settings](configuration.md).

What's left to do by hand for the hardware is listed at the end of the run. See [hardware](hardware.md).

`cc-pkg-mng status` shows what's installed and whether it's all in place. For keeping things up to date, see [cc-pkg-mng.md](cc-pkg-mng.md).

## Moving to Fedora 45

Upgrade coucou-shell first, on Fedora 44:

```bash
cc-pkg-mng upgrade
sudo dnf upgrade --refresh
sudo dnf system-upgrade download --releasever=45
sudo dnf offline reboot
```

After the reboot, `cc-pkg-mng status` checks that everything is still in place.

## Coming from an earlier setup

If this machine already has a checkout of these dotfiles, point `init` at it. It installs what's missing.

```bash
cc-pkg-mng init --dir ~/code/dotfiles
```
