# Modules

Each directory under `config/` that contains an `install.sh` is a module. The list and its order live in [`scripts/lib/modules.sh`](../scripts/lib/modules.sh); see [configuration.md](configuration.md#the-module-registry) to add one.

Every module can be run on its own:

```bash
bash config/nvim/install.sh
```

Run that way it may install packages and ask for sudo. Run through `cc-pkg-mng update`, it never asks — see [cc-pkg-mng.md](cc-pkg-mng.md#privilege-scope).

Config files are **symlinked** into place, never copied: edit the file in the repo and the change is live (after a reload of the program concerned).

## Order

```
fonts  bash  ccpkg  ccnote  ccslide  tmux  wezterm  nvim  pipewire  wireplumber
mangohud  nemo  fuzzel  fastfetch  firefox  brave  mpv  liseuse  boot/plymouth  hyprland
```

| Constraint | |
|---|---|
| `ccpkg`, `ccnote`, `ccslide` after `bash` | they rely on the shell config it installs |
| `liseuse` after `fuzzel` | its picker is fuzzel |
| `pipewire` before `wireplumber` | |
| `hyprland` last | |

A module name may be nested one level (`boot/plymouth`, `boot/login`).

Two modules are **opt-in**: never part of a default run, they must be named explicitly.

| Module | Status |
|---|---|
| `boot/login` | Replaces the system login with greetd + tuigreet. Interactive |
| `kde` | Not used on this machine. Broken upstream: its Reversal icon theme returns a 404 |

---

## Shell and terminal

### `bash`

| | |
|---|---|
| Installs | `fzf ripgrep make gcc zsh zoxide`, and `fd-find` / `fd` depending on the distro |
| Links | `~/.bashrc`, `~/.zshrc`, `~/.bash_aliases`, `~/.config/bash/prompt.zsh` |

Also clones `zsh-autosuggestions` and `zsh-syntax-highlighting` into `~/.zsh` and makes zsh the login shell.

| To change | Edit |
|---|---|
| Aliases | [`config/bash/.bash_aliases`](../config/bash/.bash_aliases) |
| Prompt | [`config/bash/prompt.zsh`](../config/bash/prompt.zsh) |

### `tmux`

Installs `tmux wl-clipboard`, links `~/.tmux.conf`.

### `wezterm`

Installs `wezterm` (from the `wezfurlong/wezterm-nightly` copr on Fedora, `apt.fury.io/wez` on Debian) and links `~/.wezterm.lua` and `~/.config/wezterm/wezterm.lua`.

Two variants are available:

| Variant | |
|---|---|
| `stable` (default) | The packaged build |
| `smear` | Built from source with a native cursor smear (wezterm PR #7737), installed to `/usr/local/bin`. nvim's own smear-cursor turns itself off under it |

```bash
cc-pkg-mng wezterm            # print the current variant
cc-pkg-mng wezterm smear      # build and switch (asks for sudo)
cc-pkg-mng wezterm stable     # back to the package
./install --wezterm=smear     # choose it at first install
```

The pinned commit and the patch are in [`config/wezterm/install.sh`](../config/wezterm/install.sh) and `config/wezterm/smear/`.

### `nvim`

| | |
|---|---|
| Installs | `neovim`, `libtexprintf-tools` (maths in Markdown), `plantuml` and Go, GTK 4 + PyGObject and python-markdown (preview windows), node/npm |
| Links | `init.lua`, `lua/`, `ftplugin/`, `colors/`, `bin/` into `~/.config/nvim/` |
| Also | `pylatexenc` through pipx, `plantuml-lsp` through `go install`, `mathjax-full` into `config/liseuse/node_modules/` |

Directories are linked whole: a new file under `config/nvim/lua/` is live without re-running anything.

| Feature | Use |
|---|---|
| Markdown live preview | `Alt + P` — a GTK 4 window (`bin/mdview`) that updates block by block, maths included |
| PlantUML | highlighting, lint, completion, and a live preview window. `:PumlFromJava` draws a class diagram from Java sources, `:PumlExport` exports it |

Every optional tool degrades gracefully: without `plantuml-lsp` there is no PlantUML completion, and without `mathjax-full` the preview shows maths as TeX source.

### `ccnote` · `ccslide`

Two small shell tools, each a Python script plus a zsh wrapper linked into `~/.config/<name>/`. `ccslide` renders Markdown slides through `mdp`, built from source when no package provides it.

### `ccpkg`

Links `bin/cc-pkg-mng` into `~/.local/bin`, as a symlink so a `git pull` updates the command. See [cc-pkg-mng.md](cc-pkg-mng.md).

---

## Desktop

### `hyprland`

The compositor, the bar and every desktop tool.

| | |
|---|---|
| Installs | ~61 packages, distro-dependent, plus three coprs on Fedora (`lionheartp/Hyprland`, `errornointernet/quickshell`, `mineiro/satty`) — each enabled only when its package is missing |
| Builds | `balise`, `prisme` + `wallpaper-filter`, `roue` — see [Rust crates](configuration.md#rust-crates) |
| Links | `hypr`, `waybar`, `quickshell`, `rofi`, `balise`, `prisme`, `roue`, `scripts`, `khal`, `theme` into `~/.config/` |
| Services | `systemd --user`: `balise`, `wallpaper-slideshow`, `slideshow-fullscreen-guard` |
| Fonts | JetBrains Mono Nerd Font, GoogleSansCode Nerd Font Mono, Phosphor, Lucide and MingCute icons, when absent |
| Cursor | Comix Cursors, built when `~/.icons/ComixCursors-White` is missing |

`--reset` removes the linked config directories before relinking them.

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

#### Idle

A zathura window visible on screen holds off the idle ladder; a book on another workspace does not. See [`readinghold.lua`](../config/hyprland/hypr/readinghold.lua).

### The bar

Quickshell, in [`config/hyprland/quickshell/bar/`](../config/hyprland/quickshell/bar/). It reloads itself when a QML file changes.

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
- The equalizer is per application: the chevron on an app's row opens its page — five bands, ten presets, an on/off switch. Up to four apps can be equalized at once (the chains come from the `pipewire` module).
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

### Rust apps

| App | Source | Use |
|---|---|---|
| **Roue** | [`roue-src`](../config/hyprland/roue-src/) | Radial wheel: press, aim, release. Power menu, power profile, display layout, actions |
| **Prisme** | [`prisme-src`](../config/hyprland/prisme-src/) | Wallpaper picker (`Super + W`). `wallpaper-filter` fits a wallpaper to each screen (fill mode by default) |
| **Balise** | [`balise-src`](../config/hyprland/balise-src/) | Network/Bluetooth daemon behind the bar's Balise drawer. `balise wifi-share <ssid>` prints a QR code |

Rebuilt by `cc-pkg-mng build` when their sources change.

### `pipewire`

Installs `pipewire pipewire-utils` and links [`50-equalizer.conf`](../config/pipewire/50-equalizer.conf): four five-band filter chains (60 / 250 / 1k / 4k / 12k Hz) used by the mixer's equalizer. **Restarts the audio stack** at the end.

Any node added to that file must keep the `eq_slot_` / `eq_out_` prefix, or the bar treats it as a real output device.

### `wireplumber`

Installs `wireplumber pipewire-utils`, links the Bluetooth policy drop-ins, `bt-audio-switch.sh` and its `systemd --user` unit. **Restarts wireplumber, pipewire and pipewire-pulse** at the end, which cuts audio for a moment.

### `nemo`

Installs `nemo nemo-fileroller xdg-desktop-portal-gtk`, sets the file-manager MIME defaults, and registers the file-chooser portal.

Also themes every GTK3 app (Nemo, the file chooser) in the bar's palette: a generated `Adwaita-dark` in `~/.local/share/themes/`, following the desktop's light/dark setting.

| To change | Edit, then re-run the module |
|---|---|
| Colours | [`theme/build-adwaita-dark.py`](../config/nemo/theme/build-adwaita-dark.py) (mapped from `quickshell/bar/theme/DrawerTheme.qml`) |
| Nemo-specific styling | [`theme/overlay.css`](../config/nemo/theme/overlay.css) — needs a Nemo restart |

Thumbnails are generated for files up to 32 MiB.

### `fuzzel`

Installs `fuzzel`, links `~/.config/fuzzel/fuzzel.ini`. This is `Super + Space`, and the picker behind Liseuse and the agenda.

### `fonts`

Downloads JetBrains Mono, Iosevka and Cascadia Code Nerd Fonts and MiSans Latin into `~/.local/share/fonts/` when absent, links the fontconfig rule, and sets the UI font through `gsettings` and `kwriteconfig6`.

### `boot/plymouth`

The boot splash: the word mark on black (**coucou** at boot, **byebye** on shutdown), a thin progress bar at boot, and the boot log one line at a time, in JetBrains Mono.

Installs the Plymouth renderers and plugins, deploys the theme to `/usr/share/plymouth/themes/coucou`, selects it and rebuilds the initramfs for every installed kernel. A kernel-install hook checks each new initramfs and reports into `dnf`'s output. System-wide: deferred in user scope.

| Tool | Use |
|---|---|
| [`make-assets.py`](../config/boot/plymouth/make-assets.py) | Regenerates the PNGs. `--width` for a panel that is not 1920 px wide (the installer suggests it when needed) |
| [`simulate.py`](../config/boot/plymouth/simulate.py) | Renders the animation to a video. `--width/--height`, `--heads 1920x1200,3840x2160` for several screens |
| [`preview.sh`](../config/boot/plymouth/preview.sh) | Shows the real splash on a spare VT. `--sweep`, `--password`, `--status`. Does not work on machines whose firmware framebuffer disappears after boot (this laptop) |

Placement and motion are in [`theme/coucou.script`](../config/boot/plymouth/theme/coucou.script). On several screens the splash is sized for the smallest one.

For a real-boot diagnosis, add `plymouth.debug` to the kernel command line and read `/var/log/plymouth-debug.log`.

---

## Applications

### `firefox`

Installs `firefox`, links `~/.config/environment.d/firefox.conf` (native Wayland), writes a policy to `/etc/firefox/policies/` (deferred in user scope).

### `brave`

Adds Brave's rpm repo, installs `brave-browser`, and writes a `.desktop` override in `~/.local/share/applications/` that adds the flags from [`config/brave/brave-flags.conf`](../config/brave/brave-flags.conf). Unknown `--enable-features` names are reported at install.

### `mpv` · `mangohud` · `fastfetch`

One package and one config each: `~/.config/mpv/mpv.conf`, `~/.config/MangoHud/MangoHud.conf`, `~/.config/fastfetch/config.jsonc`.

### `liseuse`

The reading library, on `Super + F`: resumes the book open on the current workspace, otherwise opens a picker. `F1` inside a book shows the reading manual.

| | |
|---|---|
| Installs | zathura with the mupdf, cb and djvu plugins, mupdf, libnotify; python-markdown, pymdown-extensions, Pygments, WeasyPrint; `plantuml` |
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

This needs LibreOffice, which the module does not install (`libreoffice-writer libreoffice-impress libreoffice-calc`).

Rendered Markdown is cached in `~/.cache/liseuse/md/`.

---

## Opt-in

### `boot/login`

greetd + tuigreet on VT1, replacing the display manager, with the console in JetBrains Mono. Asks before touching the system login.

```bash
./install greeter
```

| Piece | |
|---|---|
| [`greetd/`](../config/boot/login/greetd/) | greetd configuration |
| [`console/`](../config/boot/login/console/) | the console font, generated by [`make-console-font.py`](../config/boot/login/make-console-font.py) (`--cell WxH`, `--preview`) |
| [`session-splash.sh`](../config/boot/login/session-splash.sh) | keeps the word mark on screen until Hyprland draws |
| `console-setup-late.service` | re-applies the keymap and font after the splash quits |

### `kde`

A minimal Plasma session as an alternate login. Currently broken upstream (see [Order](#order)).
