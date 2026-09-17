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

`./install` exists for one reason: a bare clone has nothing on `PATH` yet. It translates its phases and delegates to [`bin/cc-pkg-mng`](bin/cc-pkg-mng), which holds the logic.

| Phase | What it does |
|---|---|
| **`system`** | Base Fedora packages and services ([`setup_fedora.sh`](setup_fedora.sh)), then the **hardware phase** — the drivers *this specific machine* needs, detected rather than hardcoded. Wants sudo. |
| **`user`** | Every module in the registry, Hyprland last. Symlinks the repo into `~/.config`. Asks for nothing already installed. |

`./install --detect` reports what the hardware detection sees and changes nothing. `./install --dry-run` prints the ordered list of modules that would run. `install_all.sh` and `setup_fedora.sh` still work when called directly.

Two modules are deliberately **opt-in** and never in the default path: `login-manager` (greetd + tuigreet — it rewrites system login and prompts interactively) and `kde`.

## Day to day — `cc-pkg-mng`

After the first install the repo maintains itself. Two commands cover almost everything:

```bash
cc-pkg-mng update     # pull, then apply only what changed
cc-pkg-mng verify     # check that everything is still in place
```

**`update` never asks for a password.** It queries before it installs — `rpm -q` needs no root and answers in milliseconds, so on a provisioned machine the package manager is not invoked at all. Anything genuinely root-owned is *deferred*: named in the summary, left for an explicit `cc-pkg-mng update --system`.

**It restarts nothing**, on purpose. Like `dnf` or `apt`, it puts files and binaries in place and leaves running processes alone; the new version takes effect the next time each one starts. What is still running old code is reported — read off `/proc`, not guessed:

```
These are still running an older version:
  balise               binary replaced since it started
                       -> systemctl --user restart balise.service
```

| Command | What it does |
|---|---|
| `cc-pkg-mng status` | what changed since each module was last applied — read-only, never fetches unless asked |
| `cc-pkg-mng update [-n]` | apply it; `-n` prints the plan and changes nothing |
| `cc-pkg-mng verify [--full]` | links, binaries, packages, systemd units; `--fix` re-runs the modules owning a problem |
| `cc-pkg-mng build [crate]` | just the Rust binaries, skipping anything unchanged |
| `cc-pkg-mng needs-restart` | re-print the staleness report |
| `cc-pkg-mng clean --cargo` | drop the build caches |

Useful flags: `--only <module>`, `--force`, `--no-pull` (apply uncommitted local work — `update` otherwise refuses to pull over a dirty tree and says so), `--adopt` (record an already-configured machine as current without running anything).

### How it knows what changed

A content fingerprint per `config/<module>/`, persisted in `~/.local/state/dotfiles/`. The file list comes from `git ls-files`, which means `.gitignore` does the exclusion work for free — `balise-src/target/` is invisible without a single hand-written rule. It hashes **contents, not mtimes**: `cp`, `git checkout` and `git stash` all rewrite those.

The Rust crates get the same treatment, keyed on the source fingerprint *and* the toolchain version, so a `cargo` upgrade invalidates everything as it should. Cargo's own incremental engine then does the real work. It simply never got the chance before: the old build path deleted its fingerprint database on every single install.

Measured on this machine:

| | Before | Now |
|---|---|---|
| Nothing changed | three full LTO builds, ~460 crates | **0.17 s**, nothing compiled |
| One crate edited | all three rebuilt | **only that one** |
| Detecting what changed | didn't exist | **0.33 s** across 18 modules |
| Build trees on disk | 2.0 GB in four copies | 1.1 GB in one |

The module list and its ordering constraints live in [`scripts/lib/modules.sh`](scripts/lib/modules.sh), and are validated against the filesystem on every invocation. A `config/*/install.sh` that is in no list fails every command immediately, naming the file — this repo once shipped a machine with no application launcher because four working modules were silently called by nothing.

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
