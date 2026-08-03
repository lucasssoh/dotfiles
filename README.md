# Dotfiles

A Fedora + [Hyprland](https://hyprland.org/) desktop, used daily, versioned like software rather than kept as a folder of config files. It leans on a dozen existing FOSS tools (see below) and replaces the ones that didn't do what I needed with two native Rust/GTK4 apps written from scratch: **[Roue](config/hyprland/roue-src)** (a radial selection wheel) and **[Prisme](config/hyprland/prisme-src)** (a wallpaper picker with its own smart-crop engine).

A deeper write-up of the design decisions (why Quickshell replaced Waybar, why Orbit is vendored instead of cloned, the HDR debugging story) lives in `portfolio-content/dotfiles/` at the repo root — not tracked in git, staged there for my portfolio site.

## What's in here

| Piece | What it does |
|---|---|
| **Hyprland** (`config/hyprland/hypr/`) | Compositor config, written in Hyprland's native **Lua** API (`hyprland.lua`, `keybinds.lua`, `windowrules.lua`, `monitors.lua`) rather than the classic `hyprland.conf` syntax |
| **Quickshell bar** (`config/hyprland/quickshell/bar/`) | The active status bar (QML) — per-monitor workspaces/HDR, animated media widget, IPC-driven zen mode |
| **Waybar** (`config/hyprland/waybar/`) | Kept installed and configured as an inert fallback, not started |
| **Roue** (`config/hyprland/roue-src/`) | Native GTK4 radial wheel (press/aim/release), drives the power menu, power-profile switcher, and display-layout switcher from the same generic widget |
| **Prisme** (`config/hyprland/prisme-src/`) | Native GTK4 wallpaper picker + a Rust smart-crop filter (`wallpaper-filter`) that recomposes wallpapers to fit each screen without cropping the subject |
| **Orbit** (`config/hyprland/orbit-vendor/`) | WiFi/Bluetooth/VPN panel — vendored from [LifeOfATitan/orbit](https://github.com/LifeOfATitan/orbit) (MIT, credit: Amadeus) rather than cloned at install time, with small local UI patches tracked in place |
| **Rofi / SwayNC / dunst / systemd services** | Launcher, notifications, and background daemons (OLED-protection wallpaper slideshow, per-workspace dashboard) |
| Everything else in `config/` | bash, tmux, wezterm, nvim, wireplumber, mangohud, nemo, fonts, mpv, firefox, KDE Plasma (alternate session) |

## Installation

1. Clone the repo:
```bash
git clone https://github.com/lucasssoh/dotfiles.git
cd dotfiles
```

2. Make the scripts executable:
```bash
chmod +x setup_fedora.sh install_all.sh
```

3. Prepare the system (Fedora):
```bash
./setup_fedora.sh
```

4. Deploy the configurations:
```bash
./install_all.sh
```

`install_all.sh` runs each module's own `install.sh` (fonts, bash, tmux, wezterm, nvim, wireplumber, mangohud, nemo), then Hyprland's, then KDE's. The Hyprland module ([`config/hyprland/install.sh`](config/hyprland/install.sh)) does the heavy lifting on its own:

- Detects the distro (Fedora/Arch/Debian) and installs the matching package set.
- Builds **Orbit, Prisme, and Roue from source** (`cargo build --release`) straight from the vendored/original sources in this repo, no external clone.
- Symlinks every config directory into `~/.config` (`hypr`, `waybar`, `quickshell`, `rofi`, `dunst`, `swaync`, `orbit`, `prisme`, `roue`, `hyprlock`, `scripts`, `khal`, `theme`) — editing a file in the repo changes the live config immediately, no re-run needed.
- Enables the custom `systemd --user` services found under `systemd/`.
- Falls back gracefully where a distro lacks a package (e.g. Quickshell isn't in apt — the script warns and points at a manual build).

Run it again anytime after pulling changes; `safe_link` skips anything already correctly linked and backs up real files instead of overwriting them. Pass `--reset` to wipe the previously-linked config directories first.

## Key bindings

AZERTY layout. The full list is in [`config/hyprland/hypr/keybinds.lua`](config/hyprland/hypr/keybinds.lua); the highlights:

| Binding | Action |
|---|---|
| `Super + Enter` | WezTerm |
| `Super + Space` | Rofi launcher |
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

After first launch, check output names with `hyprctl monitors` and adjust `config/hyprland/hypr/monitors.lua` if needed — it's symlinked, so changes apply on the next `hyprctl reload`. HDR is toggled per-screen via the bar's HDR module (backed by `waybar/scripts/hdr.sh`); getting it to look *right* (not just "on") took tracing through Hyprland's own color-management config, a Chromium HDR-video metadata bug, and an NVIDIA Wayland driver gap — see the write-up in `portfolio-content/` for the full story.
