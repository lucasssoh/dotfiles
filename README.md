# Dotfiles

A Fedora + [Hyprland](https://hyprland.org/) desktop, used daily, versioned like software rather than kept as a folder of config files. It leans on a dozen existing FOSS tools (see below) and replaces the ones that didn't do what I needed with native Rust/GTK4 apps written from scratch: **[Roue](config/hyprland/roue-src)** (a radial selection wheel), **[Prisme](config/hyprland/prisme-src)** (a wallpaper picker with its own smart-crop engine), and **[Balise](config/hyprland/balise-src)** (a WiFi/Bluetooth/Ethernet panel, replacing a vendored third-party one).

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
| **Balise** (`config/hyprland/balise-src/`) | Native GTK4 WiFi/Bluetooth/Ethernet panel — first-party, replacing the vendored Orbit it started from. No VPN, by design |
| **Rofi / SwayNC / dunst / systemd services** | Launcher, notifications, and background daemons (OLED-protection wallpaper slideshow, per-workspace dashboard) |
| Everything else in `config/` | bash, tmux, wezterm, nvim, wireplumber, mangohud, nemo, fonts, mpv, firefox, KDE Plasma (alternate session) |

## Installation

```bash
git clone https://github.com/lucasssoh/dotfiles.git
cd dotfiles
./install
```

`./install` is the single entry point. It runs two phases, in order:

| Phase | What it does |
|---|---|
| **`system`** | Base Fedora packages and services ([`setup_fedora.sh`](setup_fedora.sh)), then the **hardware phase** — the drivers *this specific machine* needs, detected rather than hardcoded. Wants sudo. |
| **`user`** | Every `config/*/install.sh` module, then Hyprland, then KDE ([`install_all.sh`](install_all.sh)). Symlinks the repo into `~/.config`. |

Phases can be run on their own — `./install user` after a `git pull`, `./install hardware` after swapping machines. `./install --detect` reports what the hardware detection sees and changes nothing. `./install --dry-run` lists what would run. The two phase scripts still work when called directly; `install` orchestrates them rather than replacing them.

One thing is deliberately **not** in the default path: `./install login-manager` (greetd + tuigreet) rewrites system login and prompts interactively, so it is opt-in.

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
- Builds **Balise, Prisme, and Roue from source** (`cargo build --release`) straight from the sources in this repo, no external clone.
- Symlinks every config directory into `~/.config` (`hypr`, `waybar`, `quickshell`, `rofi`, `balise`, `prisme`, `roue`, `khal`, `theme`) — editing a file in the repo changes the live config immediately, no re-run needed.
- Enables the custom `systemd --user` services found under `systemd/`.
- Falls back gracefully where a distro lacks a package (e.g. Quickshell isn't in apt — the script warns and points at a manual build).

Run it again anytime after pulling changes; `safe_link` skips anything already correctly linked and backs up real files instead of overwriting them. Pass `--reset` to wipe the previously-linked config directories first.

## Key bindings

AZERTY layout. The full list is in [`config/hyprland/hypr/keybinds.lua`](config/hyprland/hypr/keybinds.lua); the highlights:

| Binding | Action |
|---|---|
| `Super + Enter` | WezTerm |
| `Super + Space` | App launcher (fuzzel) |
| `Super + W` | Prisme (wallpaper picker) |
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
