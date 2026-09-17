# Modules

Each directory under `config/` that contains an `install.sh` is a module. The list, its order and its constraints live in [`scripts/lib/modules.sh`](../scripts/lib/modules.sh); see [configuration.md](configuration.md#the-module-registry) for how to add one.

Every module can be run on its own:

```bash
bash config/nvim/install.sh
```

Run that way it may install packages and will ask for sudo if something is missing. Run through `cc-pkg-mng update`, it never will — see [cc-pkg-mng.md](cc-pkg-mng.md#privilege-scope).

## Order

The order is part of the contract, not an accident:

```
fonts  bash  ccpkg  ccnote  ccslide  tmux  wezterm  nvim  wireplumber
mangohud  nemo  fuzzel  fastfetch  firefox  brave  mpv  liseuse  hyprland
```

| Constraint | Why |
|---|---|
| `ccpkg`, `ccnote`, `ccslide` after `bash` | `.zshrc` sources `~/.config/ccnote/ccnote.zsh` and `~/.config/ccslide/ccslide.zsh`, and `~/.local/bin` reaches `PATH` through `.bashrc` |
| `liseuse` after `fuzzel` | its picker *is* fuzzel |
| `hyprland` last | the desktop assembles everything above it |

Two modules are **opt-in** — never part of a default run, and must be named explicitly:

| Module | Status |
|---|---|
| `login-manager` | Rewrites system login (greetd) and prompts interactively |
| `kde` | Not used on this machine. Its Reversal icon theme upstream is a 404 as of 2026-09-16; whoever re-enables it needs to pick a replacement first |

---

## Shell and terminal

### `bash`

| | |
|---|---|
| Installs | `fzf ripgrep make gcc zsh zoxide`, plus `fd-find` / `fd` depending on the distro |
| Links | `~/.bashrc`, `~/.zshrc`, `~/.bash_aliases`, `~/.config/bash/prompt.zsh` |

Also clones `zsh-autosuggestions` and `zsh-syntax-highlighting` into `~/.zsh`, and switches the login shell to zsh if it is not already. On Debian/Ubuntu, `zoxide` has no usable package and is fetched from the upstream installer instead; the script downloads it first and runs it second, because a piped `curl | sh` hides a download failure behind `sh` exiting 0 on empty input.

### `tmux`

Installs `tmux wl-clipboard`, links `~/.tmux.conf`.

### `wezterm`

Installs `wezterm`, links `~/.wezterm.lua` and `~/.config/wezterm/wezterm.lua`. Needs a third-party repo — the `wezfurlong/wezterm-nightly` copr on Fedora, `apt.fury.io/wez` on Debian — which is only added when wezterm is genuinely absent.

### `nvim`

Installs `neovim`, links `init.lua`, `lua/`, `ftplugin/` and `colors/` into `~/.config/nvim/`. The directories are linked whole, so a new file in `config/nvim/lua/` is live without re-running anything.

### `ccnote` · `ccslide`

Two small shell tools, each a Python script plus a zsh wrapper linked into `~/.config/<name>/`. `ccslide` renders Markdown slides through `mdp`; when no package provides it, the module builds it from source, which is the only reason it installs `git make gcc` and the ncurses headers.

### `ccpkg`

Links `bin/cc-pkg-mng` into `~/.local/bin`. A symlink, never a copy — the link points into the repo, so `git pull` updates the command with nothing to rebuild. Warns if the name resolves somewhere other than `~/.local/bin`.

---

## Desktop

### `hyprland`

The largest module by a wide margin, and the one that does the heavy lifting.

| | |
|---|---|
| Installs | ~61 packages, distro-dependent, plus three coprs on Fedora (`lionheartp/Hyprland`, `errornointernet/quickshell`, `mineiro/satty`) |
| Builds | `balise`, `prisme` + `wallpaper-filter`, `roue` — from the sources in this repo, skipping any crate that has not changed |
| Links | `hypr`, `waybar`, `quickshell`, `rofi`, `balise`, `prisme`, `roue`, `hyprlock`, `scripts`, `khal`, `theme` into `~/.config/` |
| Services | Four `systemd --user` units: `balise`, `wallpaper-slideshow`, `slideshow-fullscreen-guard`, `workspace-dashboard` |

It also downloads four icon/mono fonts when absent (JetBrains Mono Nerd Font, GoogleSansCode Nerd Font Mono, Phosphor Icons, Lucide Icons — the last two resolved from the npm registry), and builds the Comix Cursors theme from upstream SVGs when `~/.icons/ComixCursors-White` does not exist.

Config directories are linked, not copied: editing a file in the repo changes the live config immediately. `hyprctl reload` picks up the Lua; quickshell watches its own QML and reloads itself.

`--reset` wipes the previously-linked config directories before relinking.

Each copr is enabled only when the package it provides is actually missing.

### `wireplumber`

Installs `wireplumber pipewire-utils` and links five files: the Bluetooth policy drop-ins, a `bt-audio-switch.sh` script, and its `systemd --user` unit. **Restarts `wireplumber`, `pipewire` and `pipewire-pulse` at the end**, which cuts audio for a moment — the one module with a visible side effect on a running session.

### `nemo`

Installs `nemo nemo-fileroller xdg-desktop-portal-gtk`, sets the file-manager MIME defaults, writes a D-Bus service file and restarts the xdg portals.

### `fuzzel`

Installs `fuzzel`, links `~/.config/fuzzel/fuzzel.ini`. This is `Super + Space`, and also the picker `liseuse` is built on.

### `fonts`

Installs no package. Downloads JetBrains Mono, Iosevka and Cascadia Code Nerd Fonts plus MiSans Latin into `~/.local/share/fonts/`, each guarded by an `fc-list` check so nothing is re-fetched. Links the fontconfig rule, then applies the UI font through `gsettings` and `kwriteconfig6`. `fc-cache` runs only if something was actually added.

---

## Applications

### `firefox`

Installs `firefox`, links `~/.config/environment.d/firefox.conf` (native Wayland). Also writes a system policy to `/etc/firefox/policies/` — the only root-owned step, deferred in user scope.

### `brave`

Adds Brave's own rpm repo and installs `brave-browser`. Rather than a config file, it generates a **user `.desktop` override** in `~/.local/share/applications/`, injecting the flags from [`config/brave/brave-flags.conf`](../config/brave/brave-flags.conf) into every `Exec=` line, field codes preserved. Brave's launcher reads no flags file of its own, so this is the mechanism that works.

The module verifies each `--enable-features` name against the installed binary and warns if one is unknown — a renamed Chromium feature is otherwise silently ignored, with no error and no effect.

### `mpv` · `mangohud` · `fastfetch`

One package and one config link each: `~/.config/mpv/mpv.conf`, `~/.config/MangoHud/MangoHud.conf`, `~/.config/fastfetch/config.jsonc` plus its image.

### `liseuse`

Installs the zathura stack (`zathura`, `zathura-pdf-mupdf`, `zathura-cb`, `zathura-djvu`, mupdf, libnotify), links `zathurarc`, `sources.conf` and the `liseuse` launcher into `~/.local/bin`, creates `~/Livres` and registers the document MIME types. `Super + F`, and `F1` inside a book for the reading manual.

Also installs `python3-markdown`, `python3-pymdown-extensions`, `python3-pygments` and `python3-weasyprint` for the Markdown half. mupdf has no markdown parser, so `md2pdf.py` renders a `.md` to a PDF first and everything downstream — dark theme, reading position, ranking — works on an ordinary document. GFM coverage comes from the pymdown extensions (tables, strikethrough, task lists, autolinks, footnotes) and the syntax highlighting is Pygments' `github-dark`, which is GitHub's own palette. Not a headless browser: nothing in these documents needs JavaScript.

Rendered PDFs are cached in `~/.cache/liseuse/md/`, keyed on the mtimes of both the source and `markdown.css`, so editing the stylesheet re-renders everything. A `.src` sidecar next to each one names the source, which is how a reading position zathura recorded against a cache filename finds its way back to the `.md` in the picker. Links between markdown documents work: `md2pdf.py` rewrites them to absolute `file://` URIs and a `liseuse-markdown.desktop` handler brings them back here.

---

## Opt-in

### `login-manager`

greetd + tuigreet, replacing the display manager. Interactive: it asks before touching system login. Creates the `greeter` user, disables gdm/sddm/lightdm, and **copies** `greetd/config.toml` to `/etc/greetd/` rather than linking it, so repo edits do not go live by themselves.

```bash
./install login-manager
```

### `kde`

A minimal Plasma session as an alternate login. Installs ~15 packages with `--allowerasing`, which is why it keeps its own install call rather than going through `pkg_ensure`: it deliberately replaces conflicting packages, and that is not a decision the shared helper should ever make on its own.

Currently broken upstream — see the table at the top of this page.
