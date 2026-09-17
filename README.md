# Dotfiles

A Fedora + [Hyprland](https://hyprland.org/) desktop, used daily, versioned like software rather than kept as a folder of config files. It leans on a dozen existing FOSS tools (see below) and replaces the ones that didn't do what I needed with native Rust/GTK4 apps written from scratch: **[Roue](config/hyprland/roue-src)** (a radial selection wheel), **[Prisme](config/hyprland/prisme-src)** (a wallpaper picker with its own smart-crop engine), and **[Balise](config/hyprland/balise-src)** (a WiFi/Bluetooth/Ethernet daemon, driving a QML panel in the bar, replacing a vendored third-party one).

A deeper write-up of the design decisions (why Quickshell replaced Waybar, why Balise replaced the vendored Orbit, the HDR debugging story) lives in `portfolio-content/dotfiles/` at the repo root — not tracked in git, staged there for my portfolio site.

## Quick start

```bash
git clone https://github.com/lucasssoh/dotfiles.git
cd dotfiles
./install
```

From then on the repo maintains itself:

```bash
cc-pkg-mng update     # pull, then apply only what changed
cc-pkg-mng verify     # check that everything is still in place
```

## Documentation

| Page | Contents |
|---|---|
| [**Installation**](docs/installation.md) | First install, the three phases, running a single module, bootstrapping |
| [**cc-pkg-mng**](docs/cc-pkg-mng.md) | Commands, options, privilege scope, restart policy, exit codes, what `verify` checks |
| [**Configuration**](docs/configuration.md) | State and logs, environment variables, the module registry, adding a module, Rust crates, change detection |
| [**Modules**](docs/modules.md) | What each module installs, links and does — one section per module |
| [**Hardware detection**](docs/hardware.md) | CPU/GPU profiles, forward rules for unreleased chips, manual follow-ups |
| [**Key bindings**](docs/keybindings.md) | The full list, AZERTY |

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
| **Liseuse** (`config/liseuse/`) | Centralised reading on SUPER+F — a fuzzel picker over `~/Livres` plus the folders in `sources.conf` (course PDFs stay in `~/courses`), ranked so the book you're mid-way through comes first. Renders through zathura + `zathura-pdf-mupdf`, one engine for PDF/EPUB/MOBI/CBZ, recolored dark from `colors.lua`. Markdown too, rendered to a dark GFM page first (`md2pdf.py`: python-markdown + Pygments' `github-dark` + WeasyPrint), cached, with links between documents still working. A session hides the bar, quiets notifications and takes a D-Bus idle inhibitor, then restores exactly what it found |
| **cc-pkg-mng** (`bin/cc-pkg-mng`) | The repo's own install/update manager: pulls, applies only the modules whose contents changed, rebuilds only the Rust crates that need it, and verifies the result. Never asks for a password in its everyday scope |
| **Rofi / SwayNC / dunst / systemd services** | Launcher, notifications, and background daemons (OLED-protection wallpaper slideshow, per-workspace dashboard) |
| Everything else in `config/` | bash, tmux, wezterm, nvim, wireplumber, mangohud, nemo, fonts, mpv, firefox, brave — plus KDE Plasma as an opt-in alternate session. See [docs/modules.md](docs/modules.md) |

## Monitors & HDR

After first launch, check output names with `hyprctl monitors` and adjust `config/hyprland/hypr/monitors.lua` if needed — it's symlinked, so changes apply on the next `hyprctl reload`. HDR is toggled per-screen via the bar's HDR module (backed by `waybar/scripts/hdr.sh`); getting it to look *right* (not just "on") took tracing through Hyprland's own color-management config, a Chromium HDR-video metadata bug, and an NVIDIA Wayland driver gap.
