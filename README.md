# Dotfiles

A Fedora + [Hyprland](https://hyprland.org/) desktop, used daily, versioned like software rather than kept as a folder of config files. It leans on a dozen existing FOSS tools (see below) and replaces the ones that didn't do what I needed with native Rust/GTK4 apps written from scratch: **[Roue](config/hyprland/roue-src)** (a radial selection wheel), **[Prisme](config/hyprland/prisme-src)** (a wallpaper picker with its own smart-crop engine), and **[Balise](config/hyprland/balise-src)** (a WiFi/Bluetooth/Ethernet daemon, driving a QML panel in the bar, replacing a vendored third-party one).

A deeper write-up of the design decisions (why Quickshell replaced Waybar, why Balise replaced the vendored Orbit, the HDR debugging story) lives in `portfolio-content/dotfiles/` at the repo root — not tracked in git, staged there for my portfolio site.

## What's in here

| Piece | What it does |
|---|---|
| **Hyprland** (`config/hyprland/hypr/`) | Compositor config, written in Hyprland's native **Lua** API (`hyprland.lua`, `keybinds.lua`, `windowrules.lua`, `monitors.lua`) rather than the classic `hyprland.conf` syntax |
| **Quickshell bar** (`config/hyprland/quickshell/bar/`) | The active status bar (QML) — per-monitor workspaces/HDR, animated media widget, IPC-driven zen mode |
| **Veille** (`config/hyprland/quickshell/bar/modules/veille/`) | A big, click-through clock overlay for late work/study sessions — grows more prominent and starts showing occasional (context-aware, bilingual) messages the later it gets. Configured via `quickshell/bar/veille.json`, hot-reloaded |
| **Waybar** (`config/hyprland/waybar/`) | Kept installed and configured as an inert fallback, not started |
| **Roue** (`config/hyprland/roue-src/`) | Native GTK4 radial wheel (press/aim/release), drives the power menu, power-profile switcher, and display-layout switcher from the same generic widget |
| **Prisme** (`config/hyprland/prisme-src/`) | Native GTK4 wallpaper picker + a Rust smart-crop filter (`wallpaper-filter`) that recomposes wallpapers to fit each screen without cropping the subject |
| **Balise** (`config/hyprland/balise-src/` + `quickshell/bar/modules/balise/`) | WiFi/Bluetooth/Ethernet panel — first-party, replacing the vendored Orbit it started from. Now split in two: a Rust daemon (NetworkManager/BlueZ behind a Unix socket) and a QML panel in the bar that talks to it. The crate's original GTK4 window still builds but nothing opens it. No VPN, by design |
| **Liseuse** (`config/liseuse/`) | Centralised reading on SUPER+F — a fuzzel picker over `~/Livres` plus the folders in `sources.conf` (course PDFs stay in `~/courses`), ranked so the book you're mid-way through comes first. Renders through zathura + `zathura-pdf-mupdf`, one engine for PDF/EPUB/MOBI/CBZ, recolored dark from `colors.lua`. A session hides the bar, quiets notifications and takes a D-Bus idle inhibitor, then restores exactly what it found |
| **Rofi / SwayNC / dunst / systemd services** | Launcher, notifications, and background daemons (OLED-protection wallpaper slideshow, per-workspace dashboard) |
| Everything else in `config/` | bash, tmux, wezterm, nvim, wireplumber, mangohud, nemo, fonts, mpv, firefox, brave — plus KDE Plasma as an opt-in alternate session |

## Installation

```bash
git clone https://github.com/lucasssoh/dotfiles.git
cd dotfiles
./install
```

`./install` delegates to [`bin/cc-pkg-mng`](bin/cc-pkg-mng). Use it for the first install, on a clone where nothing is on `PATH` yet.

| Command | What it installs | sudo |
|---|---|---|
| `./install` | Everything: system phase, then every module | yes |
| `./install system` | Base Fedora packages and services ([`setup_fedora.sh`](setup_fedora.sh)), then the hardware drivers this machine needs | yes |
| `./install hardware` | The hardware drivers only | yes |
| `./install user` | Modules, symlinks, Rust binaries — nothing root-owned | no |
| `./install login-manager` | greetd + tuigreet. Interactive | yes |

Options: `--dry-run` prints the ordered list of what would run; `--detect` prints the hardware detection and exits; `--help`.

`install_all.sh`, `setup_fedora.sh` and every `config/*/install.sh` remain executable on their own.

`login-manager` and `kde` are opt-in: they are never part of a default run and must be named explicitly.

## Usage

```bash
cc-pkg-mng update     # pull, then apply the modules whose contents changed
cc-pkg-mng verify     # check links, binaries, packages and units
```

| Command | Description |
|---|---|
| `status` | Per-module state: up to date, changed, never applied, or last run failed. Also crate staleness and any repo path no module claims. Read-only; contacts the network only with `--fetch`. Always exits 0 |
| `update` | Pulls fast-forward only, then runs the `install.sh` of every module whose fingerprint moved, in registry order |
| `verify` | Six checks: registry, symlinks, binaries, declared packages, systemd units, and with `--full` the runtime dependencies |
| `build [crate]` | Builds the Rust crates, skipping any whose sources and toolchain are unchanged. No argument means all three |
| `needs-restart` | Lists processes running a binary that has since been replaced |
| `clean --cargo` | Removes the cargo target directory and the legacy `~/.cache/*-build` trees |

### Options

| Flag | Applies to | Effect |
|---|---|---|
| `-n`, `--dry-run` | all | Print what would happen; change nothing |
| `--only <module>` | `update`, `install` | Restrict to one module. Repeatable |
| `--force` | `update`, `build` | Act even when nothing changed |
| `--no-pull` | `update` | Skip the pull and apply the working tree as it is |
| `--system` | `update` | Allow root-owned steps |
| `--adopt` | `update` | Record the current fingerprints as applied, without running anything |
| `--fetch` | `status` | Contact origin to report how many commits behind |
| `--porcelain` | `status` | `key<TAB>value` output |
| `--full` | `verify` | Also run the runtime-dependency scan |
| `--fix` | `verify` | Re-run the modules owning a hard problem |
| `--strict` | `verify`, `update` | Treat warnings and deferrals as failures |
| `-q`, `--quiet`, `--no-color`, `-V` | all | |

### Behaviour to know about

- **Privilege scope.** `update` runs in user scope. A package that is already installed is detected with `rpm -q`, which needs no root, so nothing is asked of you. A package that is genuinely missing is *deferred*: listed at the end of the run and left for `cc-pkg-mng update --system`. `install` is the reverse — system scope unless `--user`.
- **Nothing is restarted.** Files and binaries are put in place; running processes keep the version they started with. `update` ends by listing what is affected, with the command to restart each one.
- **A dirty worktree stops the pull.** `update` refuses to pull over uncommitted changes and lists them. Use `--no-pull` to apply local work without touching git.
- **A failed module is retried.** A module whose last run exited non-zero is re-run on the next `update` even if its contents have not changed.

### Exit codes

| Code | Meaning |
|---|---|
| 0 | Success. Deferred root-owned steps do not fail a run unless `--strict` is given |
| 1 | `update`: a module failed, or `--strict` with deferrals. `verify`: a hard problem, or `--strict` with warnings. Also an inconsistent registry, a dirty worktree blocking the pull, or a diverged branch |
| 2 | `verify` only: the check could not run at all (not a git repository) |

`status` always exits 0.

## Configuration

### State and logs

Everything the manager remembers lives in `${XDG_STATE_HOME:-~/.local/state}/dotfiles/`:

| File | Contents |
|---|---|
| `state.v1` | `key<TAB>value`: per-module fingerprint, exit code, duration, timestamp; per-crate build key |
| `links.ledger` | `module<TAB>source<TAB>destination`, written by `safe_link` as it runs. Read by `verify` |
| `packages.ledger` | `module<TAB>package`, written by `pkg_ensure`. Read by `verify` |
| `deferred.ledger` | Root-owned steps skipped during the last run |
| `install-*.log`, `latest.log` | Full output of each run, one file per run |

Deleting `state.v1` makes every module read as never applied; the next `update` re-runs all of them. `cc-pkg-mng update --adopt` is the opposite: it records the current state as applied without running anything.

### Environment variables

| Variable | Default | Effect |
|---|---|---|
| `STATE_DIR` | `~/.local/state/dotfiles` | Where state, ledgers and logs are written |
| `CARGO_TARGET_ROOT` | `~/.cache/dotfiles/cargo-target` | Shared cargo target directory for the three crates |
| `CCPKG_ALLOW_ROOT` | `1` | `0` defers every root-owned step instead of running it. `update` sets this itself |
| `CCPKG_MODULE` | directory name | Which module the ledgers attribute an entry to |

### The module registry

[`scripts/lib/modules.sh`](scripts/lib/modules.sh) holds the list and its constraints:

| Name | Purpose |
|---|---|
| `MODULE_ORDER` | The modules, in the order they run. The order is the contract |
| `MODULE_OPTIN` | Modules that exist but are never run by default, with the reason |
| `MODULE_AFTER` | Ordering constraints — `[liseuse]="fuzzel"`, or `"@last"` for the trailing block |
| `MODULE_LAST_BLOCK` | How many entries form that trailing block |

`registry_validate` runs on every invocation and checks four things: every registered module has an `install.sh`, every `config/*/install.sh` on disk is registered, no duplicates, and every `MODULE_AFTER` constraint holds. Any failure stops the command and names the module and the file to edit.

**To add a module:** create `config/<name>/install.sh`, then add `<name>` to `MODULE_ORDER` (or to `MODULE_OPTIN` to keep it out of default runs). Until you do, every `cc-pkg-mng` command will fail and tell you so.

Inside a module, source the shared helpers instead of writing your own:

```bash
. "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../../scripts/lib/pkg.sh"
. "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../../scripts/lib/link.sh"

pkg_ensure tmux wl-clipboard                      # installs only what is missing
pkg_ensure "$(pkg_pick fd-find fd fd-find)"       # dnf / pacman / apt name
sudo_maybe systemctl enable --now foo             # deferred in user scope
safe_link "$SRC/file.conf" "$HOME/.config/file.conf"
```

### Rust crates

`RUST_CRATES` in [`scripts/lib/rust.sh`](scripts/lib/rust.sh) maps each crate to its directory and the binaries it produces:

```bash
[prisme]="config/hyprland/prisme-src prisme wallpaper-filter"
```

A crate is rebuilt when its content fingerprint or the `cargo --version` string changes, or when one of its binaries is missing from `~/.local/bin`. `--force` bypasses the check.

### How changes are detected

One content fingerprint per `config/<module>/`, stored in `state.v1` and compared on the next run. The file list comes from `git ls-files`, so `.gitignore` decides what is excluded — build output under `*-src/target/` and `__pycache__/` never counts. Contents are hashed, not modification times, so `touch` alone triggers nothing.

Paths outside `config/` map to a target too: `setup_fedora.sh` to the system phase, `scripts/lib/hardware.sh` to the hardware phase, `wallpapers/` to the hyprland module. Changes to the manager's own scripts trigger nothing, since they are read fresh on each run. Any path matching none of these is listed by `status` under *Unmapped paths*.

### Hardware detection

[`scripts/lib/hardware.sh`](scripts/lib/hardware.sh) maps the CPU's CPUID family/model to a *profile*, and profiles to Fedora packages — because what a machine needs is driven by the microarchitecture generation, not the marketing name. Intel Gen8+ gets the iHD VAAPI driver, oneVPL and `thermald`; any Zen gets `radeontop` (Mesa already ships the AMD VAAPI drivers on Fedora 44); everything gets SOF audio firmware, `power-profiles-daemon` and the VAAPI/Vulkan diagnostics.

It is built to handle CPUs released after it was last edited. Two rules do that:

- **Intel** — family 6, model ≥ `0x8C` (Tiger Lake, the first Xe iGPU) → the modern profile. Lunar Lake, Arrow Lake, Panther Lake, Nova Lake and anything later land on it with no edit.
- **AMD** — family ≥ `0x17` (Zen) → the Zen profile. Zen 6 (expected family `0x1B`) and beyond land on it with no edit.

An unlisted CPU is reported as *matched by forward rule* rather than by name: the package set is already right, and adding the codename to the table is purely cosmetic. Anything that must **not** be automated — the NVIDIA proprietary stack (third-party repo, kmod rebuild, Secure Boot), Lenovo battery conservation mode, the `i915.enable_dpcd_backlight` workaround for OLED brightness keys — is printed as a manual follow-up instead of being run.

```bash
./scripts/hardware-detect.sh            # report + packages + follow-ups
./scripts/hardware-detect.sh --packages # bare list, one per line
./scripts/hardware-detect.sh --json     # machine-readable
```

### What the Hyprland module does

[`config/hyprland/install.sh`](config/hyprland/install.sh) does the heavy lifting of the user phase on its own:

- Detects the distro (Fedora/Arch/Debian) and installs the matching package set.
- Builds **Balise, Prisme, and Roue from source** straight from this repo, no external clone — and skips any crate whose sources and toolchain are unchanged (see above).
- Symlinks every config directory into `~/.config` (`hypr`, `waybar`, `quickshell`, `rofi`, `balise`, `prisme`, `roue`, `khal`, `theme`) — editing a file in the repo changes the live config immediately, no re-run needed.
- Enables the custom `systemd --user` services found under `systemd/`.
- Falls back gracefully where a distro lacks a package (e.g. Quickshell isn't in apt — the script warns and points at a manual build).

Safe to re-run anytime, though `cc-pkg-mng update` is the usual way in: `safe_link` ([`scripts/lib/link.sh`](scripts/lib/link.sh), shared by every module) returns early on anything already correctly linked, and backs real files up to `.bak` rather than overwriting them. Pass `--reset` to wipe the previously-linked config directories first.

## Key bindings

AZERTY layout. The full list is in [`config/hyprland/hypr/keybinds.lua`](config/hyprland/hypr/keybinds.lua); the highlights:

| Binding | Action |
|---|---|
| `Super + Enter` | WezTerm |
| `Super + Space` | App launcher (fuzzel) |
| `Super + W` | Prisme (wallpaper picker) |
| `Super + F` | Liseuse — resume the book you were reading, or pick one (`F1` inside a book for its manual) |
| `Super + Shift + F` / `Super + Ctrl + F` | Fullscreen / maximise the focused window |
| `Super + Delete` | Roue power wheel (hold to aim, release to confirm) |
| `Super + Shift + Delete` | Roue power-profile wheel |
| `Super + O` | Roue display-layout wheel |
| `Super + Z` | Zen mode (hide the bar) |
| `Super + I` | Notification center (SwayNC) |
| `Super + S` / `Super + Shift + S` | Screenshot (full / region), annotated via `satty`, copied to clipboard |
| `Super + 1..0` | Switch workspace · `+ Shift` moves the window |
| `Super + H/J/K/L` | Focus left/down/up/right · `+ Shift` moves the window |
| `Super + Escape` | Lock screen (hyprlock) |

## Monitors & HDR

After first launch, check output names with `hyprctl monitors` and adjust `config/hyprland/hypr/monitors.lua` if needed — it's symlinked, so changes apply on the next `hyprctl reload`. HDR is toggled per-screen via the bar's HDR module (backed by `waybar/scripts/hdr.sh`); getting it to look *right* (not just "on") took tracing through Hyprland's own color-management config, a Chromium HDR-video metadata bug, and an NVIDIA Wayland driver gap.
