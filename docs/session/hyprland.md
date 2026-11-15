# Hyprland

The compositor and the session around it: Hyprland, the lock screen, idle, night mode, the portals, and the wallpaper services.

## Configuration files

They're all in [`config/hyprland/hypr/`](../../config/hyprland/hypr/), linked at `~/.config/hypr/`. `hyprctl reload` (`Super + Shift + R`) applies the Lua files. After an edit, `hyprctl configerrors` lists what Hyprland didn't understand.

| File | What's in it |
|---|---|
| `hyprland.lua` | General settings, input, animations, gestures |
| `keybinds.lua` | Key bindings, listed in [key bindings](../keybindings.md) |
| `windowrules.lua` | Window rules |
| `monitors.lua` | Turns on every screen at its preferred mode. Where screens sit is in [displays](displays.md) |
| `colors.lua` | The shared colour palette |
| `hypridle.conf` | What happens [when you're idle](#idle) |
| `hyprlock.conf` | The [lock screen](lock.md) |
| `hyprsunset.conf` | hyprsunset's own settings. [Night mode](displays.md#night-mode) has its own |
| `hosts/*.env` | [Per-machine behaviour](#per-machine-profiles) |

The keyboard layout is French (`kb_layout` in `hyprland.lua`).

## Your own rules and keys

Create `~/.config/hypr/private.lua` for what belongs to this machine only: a rule for one game, a key of your own. It's loaded last, so it can override anything above. It's never committed, and an upgrade never touches it.

```lua
-- ~/.config/hypr/private.lua
hl.bind("SUPER + G", hl.dsp.exec_cmd("steam"))
hl.window_rule({ match = { class = "^(mygame)$" }, fullscreen = true })
```

Hyprland ignores a rule property it doesn't know, without an error: check the names against Hyprland's documentation.

The other files that are yours alone are listed in [your settings](../configuration.md#files-that-are-yours).

## Per-machine profiles

`hosts/default.env` is loaded on every machine. Then, if there's a `hosts/<id>.env` for this machine, it's loaded on top. The id comes from the DMI product name, or from `HOST_PROFILE` if you set it.

| Variable | Default | Effect |
|---|---|---|
| `IDLE_ENABLED` | `1` | Set it to `0` and nothing happens when idle |
| `IDLE_ALLOW` | `dim undim lock dpms-off dpms-on suspend` | The idle actions this machine is allowed to take |
| `IDLE_REQUIRE_BATTERY` | `1` | Only act when the machine has a battery |

```bash
~/.config/hypr/scripts/host-profile.sh --report    # which profile is used, and with which values
```

To add a machine, create `hosts/<id>.env` with only the values that differ from the default. Then add its product name to `host_profile_id` in [`scripts/host-profile.sh`](../../config/hyprland/hypr/scripts/host-profile.sh).

## Default applications

`Super + Enter`, `Super + E` and `Super + B` open whichever app fills that role:

| Role | Default | To change it |
|---|---|---|
| Terminal | WezTerm | List desktop ids in `~/.config/xdg-terminals.list`, favourite first (for example `kitty.desktop`) |
| Web browser | Firefox | `xdg-settings set default-web-browser brave-browser.desktop` |
| File manager | Nemo | `xdg-mime default org.gnome.Nautilus.desktop inode/directory` |

```bash
~/.config/hypr/scripts/coucou-open --print terminal   # what Super+Enter would open
```

## Idle

| After | On battery | Plugged in |
|---|---|---|
| 2 min 30 | The screen dims | |
| 5 min | Locks | |
| 5 min 30 | The screen turns off | |
| 15 min | | Locks |
| 16 min | | The screen turns off |
| 30 min | Suspends | |

Change the times in [`hypridle.conf`](../../config/hyprland/hypr/hypridle.conf): each `timeout` is in seconds. To turn an action off on one machine, use its [profile](#per-machine-profiles).

While a book is visible in [Liseuse](../tools/liseuse.md), the screen doesn't dim, lock or turn off. A book left open on another workspace doesn't count.

## Touchpad

Swipe three fingers left or right to change workspace. Scrolling is natural.
