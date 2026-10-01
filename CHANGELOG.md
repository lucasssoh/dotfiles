# Changelog

Versions follow `MAJOR.MINOR.PATCH`, and each release is a git tag (`v1.0.0`). Major and minor releases also get a name; patch releases don't. On the stable channel, `cc-pkg-mng upgrade` moves you from one release to the next.

## Unreleased

### Added
- **fontview**, a font viewer as simple as imv: open a font file from Nemo or run `fontview FILE`. `←` `→` step through the fonts in the folder, `+` `−` change the size.
- **swayimg** is the image viewer, in the shell's colours, and opens images by default. `←` `→` go through the folder, `Return` shows a gallery, and `e` opens the image in satty to crop or annotate it, saved as a copy next to the original.

### Changed
- **Balise:** pressing Scan now shows it working, a spinning ring and "Scanning" until the results are in, and an empty list reads "Searching…" meanwhile.
- **Bar, centre island:** when a track starts, the media pill opens on its title and artist for a few seconds, then folds back to the wave.
- **mpv** gets a modern interface (uosc) in the shell's colours, with a thumbnail when you hover the timeline (thumbfast). It is now set to open video and audio files, and what it plays shows in the bar's media pill, like any other player.

## 1.0.2

### Fixed
- **Bar, centre island:** right after login, the bar now shows every workspace, 1 to 5 and 6 to 10 on two screens. Before, it sometimes showed only one per screen, and the others appeared one by one as you visited them.

## 1.0.1

### Fixed
- **Bar, centre island:** a workspace no longer looks occupied once its last window is closed. Sometimes the bar missed a window closing (it happened with a Java popup) and kept counting it. It now goes by Hyprland's own window count.

## 1.0.0 « Coucou à tous »

The first version you can install on a fresh Fedora netinstall.

### Install and updates
- **Installed with dnf**, from coucou-shell's own signed repository: add `coucou-shell.repo`, install `cc-pkg-mng`, then run `cc-pkg-mng init`. Roue, Prisme and Balise come prebuilt, so you don't need the Rust toolchain.
- **cc-pkg-mng 2**, coucou-shell's package manager. `init` sets up a new machine, `install` and `remove` add or take away parts, `upgrade` and `rollback` move between releases, `channel` switches between stable (releases) and edge (every commit), and `set` changes one of your answers, like the WezTerm build.
- All the questions come first, your password is asked only once, and every package goes in a single dnf transaction.
- Everything is split into three layers: **core** (the shell itself), **apps** (default applications you can swap out), and **configs** (optional personal setups you can take or leave; any file one would replace is backed up first).
- If you used the previous manager, it picks up your checkout and what was already installed.
- The documentation is now also a website: https://lucasssoh.github.io/dotfiles/.

### Desktop
- **Hyprland**, configured in Lua, with per-machine profiles and an optional private file for your own overrides.
- **The bar** (Quickshell): clock and metrics, workspaces and media, and drawers for network and Bluetooth, power, an audio mixer with a per-application equalizer, notifications, and a calendar with an agenda (`Super + A`). Hold `Super` to see every key binding on a keyboard.
- **Veille**, a big clock that shows up when you're working late.
- **Roue**, a radial wheel for the power menu, power profiles, display layouts and actions.
- **Prisme**, the wallpaper picker. Wallpapers are fitted to the resolution of each connected screen, once at install and again whenever you plug in a new one.
- **Balise**, the network and Bluetooth service behind the bar.
- **Liseuse** (`Super + F`), a reading library for PDF, EPUB, comics and Markdown with maths and PlantUML.
- **Default applications by role**: `Super + Enter`, `Super + B` and `Super + E` open your terminal, browser and file manager, whichever ones you use.
- A GTK theme in the bar's palette, light and dark.
- An optional boot splash and an optional greetd login screen.

### Wallpapers
- Three coucou-shell wallpapers, **Aube · Plis**, **Aube · Soie** and **Aube · Relief**, up to 5K. Relief is the default on a new install.
- The GNOME default wallpapers, light and dark.

### Applications
- Installed by default, and each one can be swapped for another: WezTerm, Firefox, Nemo, Neovim, mpv.
- Optional: Brave, MangoHud, fastfetch, ccnote, ccslide.
- Optional configurations: shell (zsh and bash), WezTerm, Neovim, and a set for mpv, MangoHud, fastfetch and Brave.

### Removed
- Waybar and Rofi, replaced by the bar and fuzzel.
- The KDE Plasma session is no longer offered.

### Requirements
- Fedora 44, x86_64.

### Licence
- coucou-shell is for personal use (see `LICENSE.md`). Third-party parts keep their own licences, listed in `THIRD-PARTY.md`.
