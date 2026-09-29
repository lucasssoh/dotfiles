# cc-pkg-mng 2 — design

Status: **draft for review**. Not user documentation: this page explains the design of the next manager, so it is allowed to talk about *why*.

## Goals

1. Install **coucou-shell** on a fresh **Fedora netinstall** with nothing but `dnf`.
2. Work like a package manager: list, install, remove, upgrade, roll back.
3. Split the system into **core** (the identity of the OS), **apps** (replaceable defaults) and **configs** (Lucas's personal setups, optional).
4. Never block: every question is asked before anything runs, and the password is asked once.
5. Follow **stable** releases (git tags) by default, or **edge** (`master`).

Non-goals for 2.0: Arch and Debian (the current bash modules carry partial support; see [Open questions](#open-questions)), KDE, a GUI.

## Layers

| Layer | What it is | Config | Can the user skip it? |
|---|---|---|---|
| **core** | Hyprland, Quickshell, the Rust apps, Liseuse, and what they need | always the repo's | no, except the boot splash and the greeter |
| **apps** | default applications | the application's own defaults, untouched | yes, or replace them |
| **configs** | Lucas's personal configurations | the repo's, if adopted | yes: per config, *adopt* or *keep mine* |

Rule for splitting anything: **if the shell breaks without it, it is core; if it is a matter of taste, it is a config.** Core never writes into an application's main config file; it uses drop-in directories, environment files or files of its own.

## Units

A **unit** is the installable thing. The current 20 modules become:

### core

| Unit | From | Contents |
|---|---|---|
| `base` | `setup_fedora.sh` | base packages, Mesa, pipewire stack, dbus/polkit, xdg, GTK/Qt libraries |
| `hardware` | hardware phase | detected drivers, RPM Fusion codec swaps |
| `fonts` | `fonts` | JetBrains Mono, Iosevka, Cascadia Code, MiSans, fontconfig rule, UI font |
| `hyprland` | `hyprland` (part) | compositor, hyprlock, hypridle, hyprsunset, portal, Lua config, scripts, host profiles, wallpapers and slideshow services |
| `bar` | `hyprland` (part) | Quickshell and the bar, its helper scripts (moved out of Waybar), khal, screenshot and clipboard tools, brightness/media tools |
| `audio` | `pipewire` + `wireplumber` | equalizer chains, Bluetooth policy |
| `roue`, `prisme`, `balise` | `hyprland` (build) | the binaries (RPM) and their config/services |
| `fuzzel` | `fuzzel` | launcher and its config |
| `liseuse` | `liseuse` | zathura stack, Markdown pipeline, MathJax, PlantUML |
| `theme` | `nemo` (part), `hyprland` (part) | generated GTK3 theme, icons, cursor, Qt settings |
| `plymouth` | `boot/plymouth` | boot splash — **optional**, asked at `init` |
| `greeter` | `boot/login` | greetd + tuigreet — **optional**, asked at `init` |
| `roles` | new | `coucou-open` and the terminal adapters, see [Roles](#roles) |

### apps

Installed with their own defaults. Each is proposed at `init` and can be skipped.

| Unit | Default | Notes |
|---|---|---|
| `wezterm` | yes | question: `stable` or `smear` build |
| `firefox` | yes | package only. The one shared setting, `gfx.wayland.hdr`, is core (see [Settled](#settled)) |
| `nemo` | yes | the GTK theme lives in `theme` |
| `neovim` | yes | package only |
| `mpv` | yes | |
| `brave` | no | |
| `mangohud`, `fastfetch` | no | |
| `ccnote`, `ccslide` | no | |

### configs

Each is proposed at `init` as **adopt** or **keep mine**.

| Unit | Requires | Contents |
|---|---|---|
| `config-shell` | — | bash, zsh and its plugins, prompt, aliases, zoxide, fzf, ripgrep, fd, tmux, login shell |
| `config-wezterm` | `wezterm` | `wezterm.lua` |
| `config-nvim` | `neovim`, `liseuse` | `init.lua`, `lua/`, `ftplugin/`, `colors/`, `bin/` (Markdown and PlantUML previews included), PlantUML LSP |
| `config-extras` | — | mpv, MangoHud, fastfetch configs; each file only if its app is installed |

## Roles

Key bindings target roles, not binaries, so apps stay replaceable:

| Binding | Role | Resolved through | Default |
|---|---|---|---|
| `Super + Enter` | terminal | `xdg-terminal-exec` | WezTerm |
| `Super + B` | browser | `xdg-settings get default-web-browser` | Firefox |
| `Super + E` | files | default handler of `inode/directory` | Nemo |

`coucou-open <role> [--class <class>] [-- command…]` does the resolution. `--class` covers the floating TUIs (`nmtui`, Bluetooth, audio): the adapter knows each common terminal's flag (`--class` for WezTerm and kitty, `--app-id` for foot, …) and falls back to an unclassed window.

Window rules stay per application: rules for an app that is not installed never match, so they cost nothing.

## Manifest

One `unit.toml` per unit, under `units/<layer>/<name>/`. Payload (config files) stays where it is under `config/` and is referenced by path.

```toml
name     = "config-wezterm"
layer    = "configs"
summary  = "Lucas's WezTerm setup"
requires = ["wezterm"]

[packages]
dnf  = []
copr = []

[links]                     # repo path → destination
"config/wezterm/wezterm.lua" = "~/.config/wezterm/wezterm.lua"

[services]
user   = []
system = []

[[questions]]
id      = "variant"
ask     = "WezTerm build"
choices = ["stable", "smear"]
default = "stable"

[hooks]
user = "hooks/post.sh"      # runs as the user, stdin closed
root = ""                   # runs under the single sudo session, stdin closed

[verify]
commands = ["wezterm --version"]
```

Hooks cover what cannot be declared (Plymouth's initramfs, the GTK theme build, the wezterm smear build). They run with **stdin closed**: a hook that waits for input fails at once with a clear message instead of hanging.

## Commands

```
cc-pkg-mng init [--dir PATH] [--channel stable|edge] [--answers FILE]
cc-pkg-mng list [--installed | --available] [--layer core|apps|configs]
cc-pkg-mng info <unit>
cc-pkg-mng install <unit…>
cc-pkg-mng remove <unit…>
cc-pkg-mng adopt <config…>        # switch a config from "keep mine" to the repo's
cc-pkg-mng release <config…>      # the reverse: restore the user's files
cc-pkg-mng upgrade [--to vX.Y.Z]
cc-pkg-mng rollback
cc-pkg-mng channel [stable|edge]
cc-pkg-mng status | verify [--fix] | doctor
cc-pkg-mng needs-restart
```

Global: `-n/--dry-run`, `-y/--yes` (take defaults), `-q`, `--verbose` (stream every hook's output), `--no-color`.

## `init`

1. **Where.** Asks for the directory, default `~/coucou-shell`. If the directory already holds a clone of the repo, it is **adopted** instead of cloned again (Lucas: `--dir ~/code/dotfiles --channel edge`).
2. **What.** Clones the latest stable tag (or `master` on edge).
3. **Machine.** Runs hardware detection and shows the profile.
4. **Questions**, all of them, up front:
   - apps: which defaults to install;
   - configs: for each, *adopt* or *keep mine*, showing whether a file already exists;
   - boot splash and greeter: yes/no each;
   - unit questions (wezterm build, …).
5. **Plan.** Shows every unit, package count, links, services, hooks.
6. **Run.** One password prompt, then the whole plan.
7. **End.** Summary, what to restart, "reboot".

`--answers FILE` replays a saved set of answers for unattended installs (VM tests).

## Adopting and keeping configs

- **Adopt:** every existing file a link would replace is moved to `~/.local/state/coucou-shell/backups/<unit>/<date>/`, then the links are created.
- **Keep mine:** nothing is touched; the unit is recorded as *kept*.
- **Release / remove:** the links are removed and the most recent backup is restored.

## Versions and channels

- A release is an annotated tag `vMAJOR.MINOR.PATCH`, with a code name in its message (`v1.0.0` — *Coucou à tous*), and an entry in `CHANGELOG.md`.
- **stable** follows tags: `upgrade` moves to the newest tag, `rollback` back to the previously applied one (recorded in state).
- **edge** follows `master` with a fast-forward pull.
- Uncommitted changes block `upgrade` (unchanged from today).
- The manager's own version is its RPM version. A release may state `requires-manager = ">=2.1"`; `upgrade` refuses and says to update `cc-pkg-mng` first.

## Execution

```
resolve units and dependencies
→ ask every question
→ show the plan, confirm
→ sudo -v once (kept alive for the run)
→ enable COPRs, then ONE dnf transaction for every package
→ root hooks
→ links, user services
→ user hooks
→ verify
→ report what needs a restart
```

Only changed units are applied, as today (content fingerprints). A failed unit does not stop independent ones; it is retried on the next run.

### Display

- One line per unit: state, current step, elapsed time.
- Each hook runs in a **pseudo-terminal**. Its output goes to the log; the detail line shows the latest line with escape codes stripped and progress bars (`\r`) handled. Width follows terminal resizes.
- On failure: the last 20 lines of that unit's log, then the log path.
- Not a terminal (pipe, CI): plain lines, no redraw.

## State

`~/.local/state/coucou-shell/`: installed units and their answers, fingerprints, links and packages ledgers, backups, channel, current and previous version, logs.

The first run of 2.x migrates `~/.local/state/dotfiles/` (fingerprints, ledgers) so an existing machine is not re-applied from scratch.

## Distribution

A COPR, `lucasssoh/coucou-shell`, built from tagged sources:

| Package | Contents |
|---|---|
| `cc-pkg-mng` | the manager; requires `git` and `dnf` |
| `roue`, `prisme`, `balise` | prebuilt binaries — no Rust toolchain on user machines |

On edge, the Rust apps may still be built locally (`cc-pkg-mng build`) to test unreleased changes.

Fresh machine:

```
sudo dnf copr enable lucasssoh/coucou-shell
sudo dnf install cc-pkg-mng
cc-pkg-mng init
```

## Implementation

- **Rust**, a cargo workspace at the repo root: `crates/cc-pkg-mng`, and `roue`, `prisme`, `balise` moved from `config/hyprland/*-src/`.
- Crates: `clap` (CLI), `serde` + `toml` (manifests, state), `portable-pty` (hooks), `crossterm` (display), `inquire` or `dialoguer` (questions). `git` and `dnf` are called as commands.
- The current bash `install.sh` files are split into manifests plus hooks; most of their content becomes declarations.

## Milestones

| | Deliverable | Usable when done |
|---|---|---|
| M0 | Clean-up on the current manager: remove Waybar and Rofi, fix `update`'s missing pull, relative script links, fingerprints survive a dangling link | **done** |
| M1 | Manifests for every unit, next to the current modules | reviewable, nothing changes yet |
| M2 | Rust core: resolve, plan, questions, one dnf transaction, links, state, display | `cc-pkg-mng install/remove/status` on Lucas's machine (`--dir ~/code/dotfiles`) |
| M3 | `init`, channels, `upgrade`, `rollback`, migration from 1.x | full lifecycle on an existing machine |
| M4 | `roles` unit, key bindings moved to roles | apps replaceable |
| M5 | COPR packages | installable from `dnf` |
| M6 | VM test from a Fedora 44 netinstall with an answers file | acceptance |
| M7 | Licence, `CHANGELOG.md`, captures, tag `v1.0.0` *Coucou à tous*, release | published |

## M0 — clean-up

Scripts under `config/hyprland/waybar/` and who still uses them:

| Script | Used by | Action |
|---|---|---|
| `apps.sh` | `Launchers.qml`, `LauncherActionsState.qml` | move |
| `audio.sh` | `AudioInput/Output.qml`, `MixerState.qml`, `restore-mic-port.sh`, `roue` (`main.rs`) | move; drop the retired audio-wheel parts |
| `balise-toggle.sh` | `Network/Bluetooth/Ethernet.qml`, `shell.qml` | move |
| `fan.sh` | `Fan.qml` | move |
| `hdr.sh` | `Hdr.qml`, `HdrState.qml`, `Workspaces.qml`, `windowrules.lua`, workspace/display scripts | move |
| `performance.sh` | `keybinds.lua`, `Performance.qml`, `power-profile.sh`, `roue`, `actions.toml`, `hardware.sh` | move |
| `screenshot-region.sh` | `hyprland/install.sh` only | check, likely delete |
| `watch-reload.sh` | `hyprland.lua` | move or delete with Waybar |
| `media.sh`, `mic-status.sh`, `rofi-launcher.sh`, `monitor.sh` | nothing | delete |

Rofi: `Super + V` (clipboard), `display-layout.sh` (menu), `set_wallpaper.sh` (legacy picker), `rofi/*.rasi`, the `Rofi` window rule, and the package in `hyprland/install.sh`.

## Licence (M7)

- `LICENSE` at the root: personal use; no redistribution, modified or not; the name *coucou-shell* reserved.
- Remove `license = "MIT"` from the three `Cargo.toml`.
- Keep Orbit's MIT notice for the Balise code derived from it (`LifeOfATitan/orbit`).
- `wallpapers/` (GNOME) stays CC BY-SA 3.0, stated in `wallpapers/CREDITS.md`.

## Settled

- **Boot splash and greeter** are optional core units, both asked at `init`.
- **Waybar is removed.** Its scripts still used elsewhere move into the bar (see M0); the unused ones are deleted.
- **Rofi is removed.** The clipboard picker (`Super + V`) moves to fuzzel's dmenu mode; the display-layout menu (no caller left since the `Super + O` wheel) and the legacy `set_wallpaper.sh` picker (replaced by Prisme) are deleted.
- **Firefox is installed as is.** Its current policy is mostly taste (Google as search engine and homepage, hidden new-tab search) and goes away. One setting is shared by the shell: `gfx.wayland.hdr`, since HDR is a feature of the bar; it becomes core integration, installed only when Firefox is present, as a *default* the user can change. `MOZ_ENABLE_WAYLAND` is dropped: Firefox uses Wayland natively on a Wayland session. The policy file is copied into `/etc`, not linked into a home directory.
- **`xdg-terminal-exec`** is packaged in Fedora 44 (`xdg-terminal-exec-0.14.1-2.fc44`, main repo), so `roles` depends on it.

## Open questions

1. **Arch and Debian**: the current modules carry partial support. Drop it for 2.0 (Fedora only, as the COPR implies)?
