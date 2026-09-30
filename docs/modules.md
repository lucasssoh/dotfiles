# Units

coucou-shell is installed as **units**, in three layers: the **core** (always installed, except the login screen and the boot splash, which are optional), **applications** (the ones you pick), and **configurations** (the ones you adopt). `cc-pkg-mng info <unit>` shows exactly what a unit installs, links and runs; see [cc-pkg-mng.md](cc-pkg-mng.md) to install or remove one.

Configuration files are **linked** from the checkout, never copied: edit the file in the checkout and the change is live once the program concerned reloads.

---

## Core

### `base`

The Fedora base: shell utilities, NetworkManager, Bluetooth, the PipeWire stack, Mesa and Vulkan, input, storage (NTFS, exFAT), D-Bus and polkit, xdg, the GTK and Qt libraries, and snapd. Enables NetworkManager and Bluetooth. On a fresh machine, upgrades the system first.

### `hardware`

Drivers and tools for the detected CPU and GPU, and the RPM Fusion codec swaps for hardware video decoding. See [hardware.md](hardware.md).

### `fonts`

Downloads JetBrains Mono, Iosevka and Cascadia Code Nerd Fonts and MiSans Latin into `~/.local/share/fonts/` when absent, plus the icon fonts the bar draws with (Phosphor, Lucide, MingCute, GoogleSansCode Nerd Font Mono). Links the fontconfig rule and sets the UI font.

### `theme`

Themes every GTK3 app (Nemo, the file chooser) in the bar's palette: a generated `Adwaita-dark` in `~/.local/share/themes/`, following the desktop's light/dark setting. Also the Papirus icons, Comix Cursors (built when `~/.icons/ComixCursors-White` is missing) and the Qt settings.

| To change | Edit, then `cc-pkg-mng install theme` |
|---|---|
| Colours | [`theme/build-adwaita-dark.py`](../config/nemo/theme/build-adwaita-dark.py) (mapped from `quickshell/bar/theme/DrawerTheme.qml`) |
| Nemo-specific styling | [`theme/overlay.css`](../config/nemo/theme/overlay.css) — needs a Nemo restart |

### `audio`

Links [`50-equalizer.conf`](../config/pipewire/50-equalizer.conf) — four five-band filter chains (60 / 250 / 1k / 4k / 12k Hz) used by the mixer's equalizer — and the WirePlumber Bluetooth policy, with `bt-audio-switch` as a `systemd --user` service. **Restarts the audio stack** when this configuration changes, which cuts sound for a moment.

Any node added to the equalizer file must keep the `eq_slot_` / `eq_out_` prefix, or the bar treats it as a real output device.

### `hyprland`

The compositor and the session: Hyprland, hyprlock, hypridle, hyprsunset, the portals, brightness and power-profile tools, and the wallpaper slideshow as `systemd --user` services. Merges [`wallpapers/`](../wallpapers/) into `~/Images/Wallpapers`.

#### Configuration files

All under [`config/hyprland/hypr/`](../config/hyprland/hypr/). `hyprctl reload` (`Super + Shift + R`) applies the Lua files.

| File | Contents |
|---|---|
| `hyprland.lua` | General settings, input, animations, gestures |
| `keybinds.lua` | Key bindings — see [keybindings.md](keybindings.md) |
| `windowrules.lua` | Window rules |
| `monitors.lua` | Outputs, resolutions, positions. Check names with `hyprctl monitors` |
| `colors.lua` | The shared palette |
| `private.lua` | Machine-local overrides (per-game rules, anything not worth versioning). Git-ignored, optional, loaded last when present |
| `hypridle.conf` | Idle ladder: dim, lock, screen off, suspend |
| `hyprlock.conf` | Lock screen |
| `hyprsunset.conf` | Night mode |
| `hosts/*.env` | Per-machine behaviour, see below |
| `wallpaper-playlist.json` | Wallpaper slideshow |

#### Per-machine profiles

`hosts/default.env` is loaded on every machine, then `hosts/<id>.env` on top when one exists. The id comes from the DMI product name, or from `HOST_PROFILE` if set.

| Variable | Default | Effect |
|---|---|---|
| `IDLE_ENABLED` | `1` | `0` turns every hypridle action into a no-op |
| `IDLE_ALLOW` | `dim undim lock dpms-off dpms-on suspend` | Actions this machine may perform |
| `IDLE_REQUIRE_BATTERY` | `1` | Only act when a battery is present |

```bash
~/.config/hypr/scripts/host-profile.sh --report    # which profile, which values
```

To add a machine: create `hosts/<id>.env` with only the values that differ, and add its product name to `host_profile_id` in [`scripts/host-profile.sh`](../config/hyprland/hypr/scripts/host-profile.sh).

#### Default applications

`Super + Enter`, `Super + E` and `Super + B` open whatever application fills the role (the `roles` unit), through [`coucou-open`](../config/hyprland/hypr/scripts/coucou-open):

| Role | Default | To change it |
|---|---|---|
| Terminal | WezTerm | list desktop ids, most preferred first, in `~/.config/xdg-terminals.list` (e.g. `kitty.desktop`) |
| Web browser | Firefox | `xdg-settings set default-web-browser brave-browser.desktop` |
| File manager | Nemo | `xdg-mime default org.gnome.Nautilus.desktop inode/directory` |

```bash
~/.config/hypr/scripts/coucou-open --print terminal   # what Super+Enter would run
```

#### Idle

A zathura window visible on screen holds off the idle ladder; a book on another workspace does not. See [`readinghold.lua`](../config/hyprland/hypr/readinghold.lua).

### `bar`

Quickshell, in [`config/hyprland/quickshell/bar/`](../config/hyprland/quickshell/bar/). It reloads itself when a QML file changes. Also brings the screenshot tools (grim, slurp, satty) and the clipboard history.

| Area | Contents |
|---|---|
| Left | Clock (click: month calendar and agenda), CPU, temperature, fan (hidden when the machine has no fan sensor), memory |
| Centre island | Active window, workspaces, media |
| Launchers | Open apps. Right click on a chip: focus, close or quit |
| Right | HDR, audio output and input, network rate, Balise, power profile, battery, notifications |

#### Drawers

| Drawer | Opened by | Holds |
|---|---|---|
| Calendar | the clock | month view, khal agenda and reminders |
| Notification centre | the bell, `Super + I` | history grouped by app, do-not-disturb, media controls, clear all |
| [Balise](../config/hyprland/quickshell/bar/modules/balise/) | its button | Wi-Fi, Bluetooth, Ethernet with device lists; brightness, night mode, HDR; dark mode; screenshot |
| [Power](../config/hyprland/quickshell/bar/modules/power/) | the battery | time remaining, charge limit, fast charge, power profile, charge curve |
| [Mixer](../config/hyprland/quickshell/bar/modules/mixer/) | either audio icon | output and input levels, device lists, per-app volume, per-app equalizer |

Only one of the right-hand drawers is open at a time. Holding `Super` shows the key bindings as a live keyboard in the centre island (`Shift` switches layer).

#### Mixer and equalizer

- Right click on an audio icon opens pavucontrol, for card profiles and stream moves.
- A newly connected output or input becomes the default.
- The equalizer is per application: the chevron on an app's row opens its page — five bands, ten presets, an on/off switch. Up to four apps can be equalized at once (the chains come from the `audio` unit).
- Curves are saved per application name in `~/.local/state/bar-equalizer.json`.

#### Veille

A large clock overlay for late sessions, with occasional messages. Configured in [`quickshell/bar/veille.json`](../config/hyprland/quickshell/bar/veille.json), reloaded on save:

| Key | |
|---|---|
| `enabled`, `language`, `monitor` | on/off, message language, target output (empty = focused) |
| `showSeconds`, `showDate` | clock format |
| `messageIntervalMinutes`, `messageHoldSeconds`, `curatedRatio` | message frequency |
| `thresholds` | times at which each phase starts |
| `phases` | visibility and look per phase |
| `muteWhileGaming`, `respectZenMode` | when to stay hidden |

#### Agenda

`Super + A` adds or deletes an event through fuzzel. Events are stored by khal (config in [`config/hyprland/khal/config`](../config/hyprland/khal/config)); the calendar drawer shows them and rings their reminders.

### `roue` · `prisme` · `balise`

The three native apps. On the stable channel they are installed as packages; on edge they are built on the machine from [`roue-src`](../config/hyprland/roue-src/), [`prisme-src`](../config/hyprland/prisme-src/) and [`balise-src`](../config/hyprland/balise-src/).

| App | Use | Configuration |
|---|---|---|
| **Roue** | Radial wheel: press, aim, release. Power menu, power profile, display layout, actions | [`config/hyprland/roue/`](../config/hyprland/roue/) |
| **Prisme** | Wallpaper picker (`Super + W`). Every wallpaper is fitted to each connected screen's resolution, in `~/.cache/filtered_wallpapers/<W>x<H>/`, at install and again when a new screen is plugged in; until then that screen shows the original | [`config/hyprland/prisme/`](../config/hyprland/prisme/): `wallpapers.conf` (which folder), `wallpapers-extra.conf` (folders merged in) |
| **Balise** | Network and Bluetooth service behind the bar's Balise drawer, as a `systemd --user` service. `balise wifi-share <ssid>` prints a QR code | [`config/hyprland/balise/`](../config/hyprland/balise/) |

### `fuzzel`

The launcher (`Super + Space`), and the picker behind the clipboard history (`Super + V`), Liseuse and the agenda. Configured in [`fuzzel.ini`](../config/fuzzel/fuzzel.ini).

### `liseuse`

The reading library, on `Super + F`: resumes the book open on the current workspace, otherwise opens a picker. `F1` inside a book shows the reading manual.

| | |
|---|---|
| Installs | zathura with the mupdf, cb and djvu plugins, mupdf; the Markdown renderer (python-markdown, Pygments, WeasyPrint, MathJax); `plantuml` |
| Links | `zathurarc`, `sources.conf`, the `liseuse` launcher into `~/.local/bin` |
| Creates | `~/Livres`, the document MIME associations |

**Formats**: PDF, EPUB, MOBI, AZW3, FB2, CBZ/CBR, DjVu, XPS, Markdown and PlantUML (`.puml`). Markdown is rendered as GitHub-flavoured, with syntax highlighting, maths (`$…$`, `$$…$$`), PlantUML blocks and working links between documents.

| To change | Edit |
|---|---|
| Folders scanned (besides `~/Livres`) | [`sources.conf`](../config/liseuse/sources.conf), one path per line |
| Reader keys and colours | [`zathurarc`](../config/liseuse/zathurarc) |
| Markdown page style | [`markdown.css`](../config/liseuse/markdown.css) |

In the picker, the book in progress comes first, and search matches the full path as well as the title (`md`, `dotfiles keybind`). Light and dark follow the desktop setting. `Space` / `Return` turn the page, `Shift` goes back.

A book opens as an ordinary window; `Super + Shift + F` for fullscreen. While reading, notifications are silenced, and the screen stays on while a book is visible (see [Idle](#idle)).

Office documents are converted on demand, to a PDF next to the original:

```bash
liseuse convert [FILE…]    # no argument: pick from what was found
```

This needs LibreOffice, which is not installed with Liseuse (`libreoffice-writer libreoffice-impress libreoffice-calc`).

Rendered Markdown is cached in `~/.cache/liseuse/md/`.

### `plymouth`

*Optional.* The boot splash: the word mark on black (**coucou** at boot, **byebye** on shutdown), a thin progress bar at boot, and the boot log one line at a time, in JetBrains Mono. Installing it selects the theme and rebuilds the initramfs of every installed kernel; each new kernel's initramfs is checked as it is installed.

| Tool | Use |
|---|---|
| [`make-assets.py`](../config/boot/plymouth/make-assets.py) | Regenerates the PNGs. `--width` for a panel that is not 1920 px wide |
| [`simulate.py`](../config/boot/plymouth/simulate.py) | Renders the animation to a video. `--width/--height`, `--heads 1920x1200,3840x2160` for several screens |
| [`preview.sh`](../config/boot/plymouth/preview.sh) | Shows the real splash on a spare VT. `--sweep`, `--password`, `--status`. Does not work on machines whose firmware framebuffer disappears after boot |

Placement and motion are in [`theme/coucou.script`](../config/boot/plymouth/theme/coucou.script). On several screens the splash is sized for the smallest one.

For a real-boot diagnosis, add `plymouth.debug` to the kernel command line and read `/var/log/plymouth-debug.log`.

### `greeter`

*Optional.* greetd + tuigreet on VT1 as the login screen, replacing any other display manager, with the console in JetBrains Mono.

```bash
cc-pkg-mng install greeter
```

| Piece | |
|---|---|
| [`greetd/`](../config/boot/login/greetd/) | greetd configuration |
| [`console/`](../config/boot/login/console/) | the console font, generated by [`make-console-font.py`](../config/boot/login/make-console-font.py) (`--cell WxH`, `--preview`) |
| [`session-splash.sh`](../config/boot/login/session-splash.sh) | keeps the word mark on screen until Hyprland draws |

---

## Applications

Each one is only the application. Any other app can take its place: install it, then make it the default for its role (see [Default applications](#default-applications)).

### `wezterm`

The terminal. Two builds:

| Variant | |
|---|---|
| `stable` (default) | The packaged build |
| `smear` | Built from source with a native cursor smear (wezterm PR #7737), installed to `/usr/local/bin`. Neovim's own smear-cursor turns itself off under it |

```bash
cc-pkg-mng set wezterm variant smear
cc-pkg-mng install wezterm
```

### `firefox`

The default browser, with a system policy in `/etc/firefox/policies/`.

### `brave`

From Brave's own repository. Not installed by default.

### `nemo`

The default file manager: handles folders and `org.freedesktop.FileManager1`, with thumbnails for files up to 32 MiB.

### `neovim`

The editor, without configuration — see [`config-nvim`](#config-nvim) for one.

### `mpv` · `mangohud` · `fastfetch`

The media player (default), the gaming overlay with GOverlay, and the system summary. Their configurations are in [`config-extras`](#config-extras).

### `ccnote` · `ccslide`

Two small shell tools: quick notes, and Markdown slides in the terminal through `mdp` (built from source, as Fedora does not package it). Not installed by default.

---

## Configurations

Personal setups, adopted or not at `init`. Adopting one moves every file it replaces to the backups; `cc-pkg-mng remove` puts them back.

### `config-shell`

zsh and bash with the prompt, aliases, zoxide, fzf, ripgrep, fd, and tmux. Makes zsh the login shell, with zsh-autosuggestions and zsh-syntax-highlighting.

| To change | Edit |
|---|---|
| Aliases | [`config/bash/.bash_aliases`](../config/bash/.bash_aliases) |
| Prompt | [`config/bash/prompt.zsh`](../config/bash/prompt.zsh) |
| tmux | [`config/tmux/.tmux.conf`](../config/tmux/.tmux.conf) |

### `config-wezterm`

The WezTerm setup: [`config/wezterm/wezterm.lua`](../config/wezterm/wezterm.lua).

### `config-nvim`

The Neovim setup: `init.lua`, `lua/`, `ftplugin/`, `colors/`, `bin/` linked into `~/.config/nvim/`. Directories are linked whole: a new file under `config/nvim/lua/` is live at once.

| Feature | Use |
|---|---|
| Markdown live preview | `Alt + P` — a GTK 4 window that updates block by block, maths included |
| PlantUML | highlighting, lint, completion, and a live preview window. `:PumlFromJava` draws a class diagram from Java sources, `:PumlExport` exports it |

Every optional tool degrades gracefully: without `plantuml-lsp` there is no PlantUML completion, and without MathJax the preview shows maths as TeX source.

### `config-extras`

The configurations for mpv, MangoHud, fastfetch and Brave — each only when that app is installed: `~/.config/mpv/mpv.conf`, `~/.config/MangoHud/MangoHud.conf`, `~/.config/fastfetch/config.jsonc`, and Brave's flags from [`config/brave/brave-flags.conf`](../config/brave/brave-flags.conf).
