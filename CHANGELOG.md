# Changelog

Versions follow `MAJOR.MINOR.PATCH`. Each release is a git tag (`v1.0.0`) with a code name; `cc-pkg-mng upgrade` moves between them on the stable channel.

## 1.0.0 — Coucou à tous

*Unreleased.* The first version installable on a fresh Fedora netinstall.

### Install and updates
- **cc-pkg-mng 2**, the package manager of coucou-shell: `init` sets up a new machine, `install` and `remove` add or take away parts, `upgrade` and `rollback` move between releases, `channel` switches between stable (releases) and edge (every commit), `set` changes an answer such as the WezTerm build.
- Everything is asked up front, the password is asked once, and packages install in a single dnf transaction.
- The system is split in three layers: **core** (the shell itself), **apps** (default applications, replaceable), and **configs** (optional personal setups; each can be adopted or skipped, and files it would replace are backed up).
- Picks up an existing checkout and the state of the previous manager.

### Desktop
- **Hyprland**, configured in Lua, with per-machine profiles and an optional private override file.
- **The bar** (Quickshell): clock and metrics, workspaces and media, and drawers for network and Bluetooth, power, an audio mixer with a per-application equalizer, notifications, and a calendar with an agenda (`Super + A`). Holding `Super` shows the key bindings as a keyboard.
- **Veille**, a large clock overlay for late sessions.
- **Roue**, a radial wheel for the power menu, power profiles, display layouts and actions.
- **Prisme**, the wallpaper picker. Wallpapers are fitted to every connected screen's resolution, prepared at install and again when a screen is plugged in.
- **Balise**, the network and Bluetooth service behind the bar.
- **Liseuse** (`Super + F`), a reading library for PDF, EPUB, comics and Markdown with maths and PlantUML.
- **Default applications by role**: `Super + Enter`, `Super + B` and `Super + E` open the user's terminal, browser and file manager.
- A GTK theme in the bar's palette, light and dark.
- An optional boot splash and an optional greetd login screen.

### Wallpapers
- Three coucou-shell wallpapers, **Aube · Plis**, **Aube · Soie** and **Aube · Relief**, up to 5K. Relief is the default on a new install.
- The GNOME default wallpapers, light and dark.

### Applications
- Installed by default, each replaceable: WezTerm, Firefox, Nemo, Neovim, mpv.
- Optional: Brave, MangoHud, fastfetch, ccnote, ccslide.
- Optional configurations: shell (zsh and bash), WezTerm, Neovim, and a set for mpv, MangoHud, fastfetch and Brave.

### Removed
- Waybar and Rofi: the bar and fuzzel replace them.
- The KDE Plasma session is no longer offered.

### Requirements
- Fedora 44, x86_64.

### Licence
- coucou-shell is for personal use; see `LICENSE.md`. Third-party parts keep their own licences, listed in `THIRD-PARTY.md`.
