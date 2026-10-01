# cc-pkg-mng 2: design

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
| `plymouth` | `boot/plymouth` | boot splash, **optional**, asked at `init` |
| `greeter` | `boot/login` | greetd + tuigreet, **optional**, asked at `init` |
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
| `config-shell` | | bash, zsh and its plugins, prompt, aliases, zoxide, fzf, ripgrep, fd, tmux, login shell |
| `config-wezterm` | `wezterm` | `wezterm.lua` |
| `config-nvim` | `neovim`, `liseuse` | `init.lua`, `lua/`, `ftplugin/`, `colors/`, `bin/` (Markdown and PlantUML previews included), PlantUML LSP |
| `config-extras` | | mpv, MangoHud, fastfetch configs; each file only if its app is installed |

## Roles

Key bindings target roles, not binaries, so apps stay replaceable:

| Binding | Role | Resolved through | Default |
|---|---|---|---|
| `Super + Enter` | terminal | `xdg-terminal-exec` | WezTerm |
| `Super + B` | browser | `xdg-settings get default-web-browser` | Firefox |
| `Super + E` | files | default handler of `inode/directory` | Nemo |

`coucou-open <role> [--class <class>] [-- command…]` does the resolution; it lives in `config/hyprland/hypr/scripts/`, so both managers ship it. With no terminal preference in the config dirs (`xdg-terminals.list`, `<desktop>-xdg-terminals.list`), it opens WezTerm when installed. The distro's own list orders nothing, and would pick kitty over WezTerm alphabetically. `--class` covers floating TUIs: the adapter knows each common terminal's flag (`--class` for WezTerm, kitty, Alacritty, Ghostty; `--app-id` for foot), since their desktop entries do not declare one for `xdg-terminal-exec`. Every role falls back to a working launcher when its standard piece is missing. `--print` shows the command instead of running it.

Window rules stay per application: rules for an app that is not installed never match, so they cost nothing.

## Manifest

One `unit.toml` per unit, under `units/<layer>/<name>/`. Payload (config files) stays where it is under `config/` and is referenced by path. `scripts/check-units.py` validates every manifest against the repo (`--packages` also checks every package name against dnf); `units/legacy-map.toml` records which units take over each current module.

```toml
name     = "config-wezterm"
layer    = "configs"               # core | apps | configs
summary  = "Lucas's WezTerm setup"
requires = ["wezterm"]
optional = false                   # core only: asked at init (with `ask`)
default  = true                    # apps only: preselected at init

[packages]
dnf   = []                         # installed in the single dnf transaction
copr  = []                         # enabled before it
repos = []                         # .repo file URLs, added before it
build = []                         # edge only: build dependencies of [binaries]

[binaries]                         # Rust apps: RPM on stable, local build on edge
rpm    = "roue"
source = "config/hyprland/roue-src"
bins   = ["roue"]

[links]                            # repo path → destination (user scope)
"config/wezterm/wezterm.lua" = "~/.config/wezterm/wezterm.lua"

[links_if]                         # links made only when that unit is installed
wezterm = ["config/wezterm/wezterm.lua"]

[files]                            # repo path → system path, copied as root
"config/greetd/config.toml" = "/etc/greetd/config.toml"

[services]
user   = []
system = []

[[questions]]                      # asked at init, before anything runs
id      = "variant"
ask     = "WezTerm build"
choices = ["stable", "smear"]
default = "stable"

[[hooks]]                          # what cannot be declared; stdin closed
name   = "smear-build"
run_as = "root"                    # root: needs the sudo session (see below)
does   = "build the smear variant when variant = smear"
from   = "config/wezterm/install.sh"   # the script that did it before
run    = "units/apps/wezterm/hooks/smear-build.sh"
watch  = ["config/wezterm/smear"]  # a change here re-runs the hook
```

A `# review:` comment in a manifest marks something the current modules do that is questionable or broken, recorded rather than silently changed.

A hook runs when its unit is new or its fingerprint changed. The fingerprint covers the manifest's directory (hooks included), every linked or copied source, every hook's `run` script and `watch` paths, and the unit's answers, so a changed answer re-runs the hooks. A hook without `run` is only described: the plan shows it as not extracted yet.

Every hook runs **as the user**, from the repo root, stdin closed, with `COUCOU_DIR`, `CCPKG_UNIT`, `CCPKG_HOOK_STATE` (a directory of its own) and one `CCPKG_ANSWER_<ID>` per answer. `run_as = "root"` means the hook needs root for some steps: the manager then holds a sudo session for the run, and the hook calls `sudo -n` for exactly those steps. Building or cloning as root would land in `/root`. Hooks source `units/lib/hook.sh`.

Plymouth, the greeter and the hardware phase reuse their existing scripts as hooks and declare no `[files]`: Plymouth's script rebuilds the initramfs only when what goes into it changed, so files copied ahead of it would hide the change.

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
cc-pkg-mng set <unit> <question> <value>   # e.g. set wezterm variant smear; `install <unit>` applies it
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

`--answers FILE` replays a saved set of answers for unattended installs (VM tests):

```toml
dir     = "~/coucou-shell"
channel = "stable"
units   = ["plymouth", "wezterm", "config-shell"]   # optional core, apps, configs to take
[answers.wezterm]
variant = "smear"
```

Core units that are not optional are always installed. `init` refuses a machine that already has a channel and units; a state with units but no channel (installed by an earlier 2.x build) is completed rather than refused.

**Migration from 1.x**: when `~/.local/state/dotfiles/state.v1` exists and 2.x has no unit recorded yet, every module 1.x applied successfully (`mod.<name>.rc = 0`) preselects the units `units/legacy-map.toml` maps it to, and `wezterm.variant` becomes the wezterm answer. The plan then finds almost everything already in place and records it.

## Adopting and keeping configs

- **Adopt:** every existing file a link would replace is moved to `~/.local/state/coucou-shell/backups/<unit>/<date>/`, then the links are created.
- **Keep mine:** nothing is touched; the unit is recorded as *kept*.
- **Release / remove:** the links are removed and the most recent backup is restored.

## Versions and channels

- A release is an annotated tag `vMAJOR.MINOR.PATCH` with an entry in `CHANGELOG.md`. Major and minor releases carry a name in the tag message and the changelog heading (`v1.0.0 « Coucou à tous »`); patch releases don't.
- **stable** follows tags: `upgrade` checks out the newest tag (detached), `upgrade --to vX.Y.Z` a given one, `rollback` the one before the last upgrade (recorded in state).
- **edge** follows the remote's default branch with a fast-forward; `rollback` is refused there (check out a commit with git).
- After the checkout moves, every installed unit is re-applied, core units the new version adds are installed, and units the version no longer has are dropped from the state (their links left as they are).
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
- Every command (dnf, cargo, hooks) runs with stdin closed and its output piped, not on a pseudo-terminal: off a terminal, dnf and cargo drop their own progress bars, which is the cleaner result. Output goes to the log; the detail line shows the latest line with escape codes stripped and `\r` redraws collapsed, cut to the width read at each line.
- On failure: the last 20 lines of that unit's log, then the log path.
- Not a terminal (pipe, CI): plain lines, no redraw.

## State

`~/.local/state/coucou-shell/`: installed units and their answers, fingerprints, links and packages ledgers, backups, channel, current and previous version, logs.

The first run of 2.x migrates `~/.local/state/dotfiles/` (fingerprints, ledgers) so an existing machine is not re-applied from scratch.

## Binaries and channels

Git carries text only (configs, QML, Lua, scripts, manifests). The Rust apps reach machines as RPMs from coucou-shell's own dnf repository. A release ties the two together:

```
                    tag v1.2.0
                        │
        ┌───────────────┴────────────────┐
        ▼                                ▼
   git (the repo)                    dnf repo (Pages)
   configs, QML, Lua, scripts,       roue, prisme, balise,
   manifests                         built from that same tag
        │                                │
        └──────── cc-pkg-mng upgrade ────┘
```

- Pushing a tag builds and signs the RPMs of `cc-pkg-mng`, `roue`, `prisme` and `balise` from that tag (`.github/workflows/release.yml`); their RPM version is the release version.
- A release's manifests state the binary versions they need (`roue = "1.2.0"`). `upgrade` checks out the tag and moves the RPMs in the same dnf transaction as every other package, so configs and binaries never drift apart.

| Channel | Configs | Rust apps |
|---|---|---|
| **stable** | the tag | RPMs matching the tag, no Rust toolchain on the machine |
| **edge** | `master` | built locally into `~/.local/bin` when absent, since `master` is ahead of the last published RPM |
| **rollback** | the previous tag | `dnf downgrade` to that tag's RPMs (the repository keeps every release) |

RPMs rather than raw binaries attached to GitHub releases: dnf installs their system dependencies (gtk4-layer-shell, libnm, bluez), they are signed, `dnf remove` cleans up, and they land in `/usr/bin`, which the Hyprland session's `PATH` already has.

Later, if edge ever needs to work without a Rust toolchain: builds on every `master` commit ("nightly"). Not needed for 1.0.

## Distribution

Not a COPR: COPR only hosts freely redistributable software, and coucou-shell's licence forbids redistribution. The repository is coucou-shell's own, served from GitHub Pages next to the documentation, built from tagged sources:

| Package | Contents |
|---|---|
| `cc-pkg-mng` | the manager; requires `git` and `dnf` |
| `roue`, `prisme`, `balise` | prebuilt binaries, no Rust toolchain on user machines |

On edge, the Rust apps are built locally from the checkout. Switching to stable removes those builds so the RPMs' binaries take over.

Fresh machine:

```
sudo dnf config-manager addrepo --from-repofile=https://lucasssoh.github.io/dotfiles/coucou-shell.repo
sudo dnf install cc-pkg-mng
cc-pkg-mng init
```

## Implementation

- **Rust**, a cargo workspace at the repo root: `crates/cc-pkg-mng`, and `roue`, `prisme`, `balise` moved from `config/hyprland/*-src/`.
- Crates: `clap` (CLI), `serde` + `toml` (manifests, state), `dialoguer` (questions), `sha2` (fingerprints), `terminal_size` + `unicode-width` (display). `git`, `rpm`, `dnf`, `systemctl` and `sudo` are called as commands.
- `CCPKG_STATE_DIR` overrides the state directory (tests).
- The current bash `install.sh` files are split into manifests plus hooks; most of their content becomes declarations.

## Milestones

| | Deliverable | Usable when done |
|---|---|---|
| M0 | Clean-up on the current manager: remove Waybar and Rofi, fix `update`'s missing pull, relative script links, fingerprints survive a dangling link | **done** |
| M1 | Manifests for every unit, next to the current modules (`units/`, checked by `scripts/check-units.py`) | **done**: reviewable, nothing changes yet |
| M2 | Rust core: resolve, plan, questions, one dnf transaction, links, state, display (`crates/cc-pkg-mng`) | **done**: `list/info/install/remove/status` on Lucas's machine; hooks run once they have a `run` script |
| M2b | Every hook extracted into a script (`run`), `watch`, `repos` | **done**: no step left to the old modules |
| M3 | `init`, channels, `upgrade`, `rollback`, `set`, migration from 1.x | **done**: tested on a simulated fresh machine with local releases |
| M4 | `roles` unit, key bindings moved to roles | **done**: apps replaceable |
| M5 | RPMs in coucou-shell's own dnf repository | installable from `dnf` |
| M6 | VM test from a Fedora 44 netinstall with an answers file | acceptance |
| M7 | Licence, `CHANGELOG.md`, captures, tag `v1.0.0` *Coucou à tous*, release | published |

## M0: clean-up

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

- `LICENSE.md` at the root: personal use; no redistribution, modified or not; the name *coucou-shell* reserved.
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

1. **Arch and Debian**: the current modules carry partial support. Drop it for 2.0 (Fedora only, as the RPMs imply)?
