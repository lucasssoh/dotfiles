# Changelog

Versions follow `MAJOR.MINOR.PATCH`, and each release is a git tag (`v1.0.0`). Major releases also get a code name, minor ones their date; patch releases have neither. On the stable channel, `cc-pkg-mng upgrade` moves you from one release to the next.

## Unreleased

### Fixed
- **cc-pkg-mng and dnf:** on the day a release comes out, `sudo dnf upgrade` and `cc-pkg-mng upgrade` now see it. dnf used to keep its list of coucou-shell's packages for two days, so the new `cc-pkg-mng` did not show up and an upgrade could fail to find the release's packages. dnf now checks coucou-shell's repository at most an hour after a release, and `cc-pkg-mng upgrade` re-reads it before installing. Your next upgrade updates the repository's settings on your machine.
- **Games, NVIDIA:** games that use DLSS, such as Kingdom Come: Deliverance II or The Witcher 3, start right after boot. Before, they reported an incompatible GPU until you had run `nvidia-smi` once. If you install the NVIDIA driver yourself later, this works from the next restart.

## 1.3.0 (October 3 2026)

### Changed
- **cc-pkg-mng, installing and upgrading:** the work shows as a live list instead of a scroll of lines. Everything to do is listed from the start, the part in progress unfolds with its steps and a spinner, finished parts fold to one line with their time, and a bar at the top counts them with the time elapsed. Package installs show how many packages are done. If something fails, it stays unfolded with its last lines and where the full log is.
- **cc-pkg-mng, help:** `cc-pkg-mng` alone or `--help` shows the coucou logo and the commands grouped by what they are for, from everyday upgrades to setting up a machine.
- **cc-pkg-mng, version:** `cc-pkg-mng --version` also says which release this machine runs, on which channel, whether a newer one is out, and which apps run from your checkout. `-V` still prints the bare version.
- **cc-pkg-mng, init:** setting up a machine opens on the logo and numbers its steps (where, channel, applications, summary), and every question has a clearer look.

## 1.2.2

### Fixed
- **cc-pkg-mng:** a background service that an upgrade adds now starts right away, instead of waiting for your next login. After updating to 1.2.0, Manette stayed off until then, so the controller menu did nothing.

## 1.2.1

### Fixed
- **cc-pkg-mng:** `cc-pkg-mng upgrade` no longer leaves Hyprland's red "hyprland.lua: No such file or directory" banner on screen. Hyprland now reloads once, on the new version, when the upgrade has put it in place. The same goes for `rollback` and for switching channels.

## 1.2.0 (October 3 2026)

### Added
- **Game controllers:** Xbox, PlayStation, Switch and Steam controllers work in the shell, over USB or Bluetooth, and so does any other controller Linux recognises as one. Nothing to set up: plug it in or pair it and it is there.
- **Game controllers, Xbox over USB:** after this update, restart your computer once, so the Xbox controller driver loads. Until then a wired Xbox controller stays off.
- **Game controllers, Xbox over Bluetooth:** if the Xbox button keeps blinking and the controller drops the connection, its firmware is too old for Linux. Update it once from the Xbox Accessories app on Windows or from an Xbox console, and it then pairs and reconnects on its own.
- **Game controllers, arrival:** when a controller connects, a pill at the bottom of the screen shows its name, how it is connected, its battery when it reports one, and which button opens the menu.
- **Bar, right-hand group:** while a controller is connected, its silhouette sits next to `hdr` and fills up from the left like a battery gauge. It turns green while charging and red under 15 %. A wired controller with no battery to report is drawn as an outline, and two controllers show two silhouettes.
- **Controller menu:** the Guide button (the Xbox, PS, Steam or Home logo) opens a menu on the screen you are using. A controller without a Guide button opens it with `Select` + `Start` held together. Guide again, or `B`, closes it.
- **Controller menu, over a game:** while Steam or a fullscreen window has focus, a short press on Guide is left to the game; hold Guide to open the menu. The press that wakes a controller up never opens it.
- **Controller menu, while open:** the game behind receives nothing from the controller, so nothing you do in the menu reaches it. The keyboard (arrows, `Return`, `Esc`, `Tab`) and the mouse work in it too.
- **Controller menu, Continue:** the menu opens on the game you played last, with its artwork, its launcher and when you last played it. `A` starts it.
- **Controller menu, Library:** your other games in one row, Steam and Lutris together with their covers, plus the games other launchers (Heroic, Bottles, itch) add to the applications menu. Each card says where the game comes from. Tools filed as games, such as GOverlay, are left out.
- **Controller menu, Launchers:** a shortcut for each launcher installed among Steam, Lutris, Heroic, Bottles and itch. Steam opens in Big Picture, and Lutris shows how many games it has.
- **Controller menu, System:** Apps, Sleep, and Turn off, which disconnects a Bluetooth controller so it switches off.
- **Controller menu, starting games:** games start straight from the menu. A Lutris game starts without the Lutris window, and Steam starts quietly in the background for its games, without its library.
- **Controller menu, all apps and games:** `Y` opens a grid of every application and game, with a tab for All, one for Games and one for each launcher, each with its count. `LT` `RT` switch tabs, `X` jumps to the next letter, `B` goes back.
- **Controller menu, buttons:** the menu draws the buttons of the controller in your hands: coloured letters on an Xbox controller, the four shapes on a PlayStation one, letters on Switch and Steam controllers, and dots marking the position on a controller it does not know. Shoulder buttons and triggers carry their own names (`LB` `RB`, `L1` `R1`, `L` `R`, `LT` `RT`, `L2` `R2`, `ZL` `ZR`). On every controller the bottom button opens and the right one goes back, so on a Switch controller `B` opens.
- **Controller menu, moving around:** the d-pad or the left stick moves the selection the way the menu is laid out, and holding a direction keeps moving. Each row remembers where you were in it.
- **Controller menu, volume:** `LB` `RB` (or `L1` `R1`, `L` `R`) turn the volume down and up from anywhere in the menu; the level shows in the menu and on the usual dial.
- **Controller menu, key binding:** `qs -c bar ipc call bar controllerMenu` opens or closes the menu without a controller, so you can bind it to a key.
- **Steam and Lutris** can be installed together as the `games` unit. It is not installed by default.
- **cc-pkg-mng:** `cc-pkg-mng dev roue` runs Roue built from the checkout you're working in, in place of the release's, on the stable channel. Your shortcuts and the bar pick it up straight away, with nothing to change in your configuration, and running it again after an edit takes a couple of seconds. `cc-pkg-mng dev` shows what is running, and `cc-pkg-mng dev --off` puts the release's Roue, Prisme and Balise back. It works for Prisme and Balise too.

## 1.1.1

### Fixed
- **Roue, Prisme and Balise on the stable channel:** their shortcuts, the bar's buttons and Balise's background service work again after you install or upgrade. Moving to stable used to remove the copies the session starts them from, so nothing opened.
- **Liseuse:** in a book, `Space` now scrolls exactly one screen instead of jumping to the next page. Before, it landed halfway down the next page and could skip the end of the current one. On slides, `Space` still turns the page.

## 1.1.0 (October 1 2026)

### Added
- **fontview**, a font viewer as simple as imv: open a font file from Nemo or run `fontview FILE`. `←` `→` step through the fonts in the folder, `+` `−` change the size.
- **swayimg** is the image viewer, in the shell's colours, and opens images by default. `←` `→` go through the folder, `Return` shows a gallery, and `e` opens the image in satty to crop or annotate it, saved as a copy next to the original.

### Changed
- **Balise:** pressing Scan now shows it working, a spinning ring and "Scanning" until the results are in, and an empty list reads "Searching…" meanwhile.
- **Bar, centre island:** when a track starts, the media pill opens on its title and artist for a few seconds, then folds back to the wave.
- **Bar, centre island:** while music plays, each bar of the media wave has its own colour, a dusk spectrum from indigo to amber that leans toward the colours of the cover. Paused, the wave goes back to cream like the rest of the bar.
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
