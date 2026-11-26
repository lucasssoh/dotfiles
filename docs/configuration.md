# Settings

Where each setting lives, and how to keep a change through an upgrade.

## User files

Local to the machine. Ignored by upgrades. A missing file means the defaults.

| File | Sets | Guide |
|---|---|---|
| `~/.config/hypr/private.lua` | User window rules and keys | [Hyprland](session/hyprland.md#user-rules-and-keys) |
| `~/.config/hypr/bar.json` | The bar's position, style, shapes, colours and shared corner radius | [Position](bar/index.md#position), [look](bar/island.md#its-look) |
| `~/.config/hypr/shell-theme.json` | The shell-wide look, `default` or `cartoon`, and its theme | [Theme and fonts](session/theme.md#the-shell-theme) |
| `~/.config/hypr/themes/*.json` | Your cartoon themes, one file each | [Theme files](session/theme.md#theme-files) |
| `~/.config/hypr/bar-radius` | Generated from `bar.json`: Hyprland's window rounding | [Look](bar/island.md#its-look) |
| `~/.config/hypr/monitor-layout.json` | Where the screens sit | [Displays](session/displays.md#where-they-sit) |
| `~/.config/hypr/scale.json` | The scale of each screen | [Displays](session/displays.md#scale) |
| `~/.config/hypr/display-layout.json` | Which screens are on, and which is the main one | [Displays](session/displays.md#which-screens-are-on) |
| `~/.config/wezterm/local.lua` | Your WezTerm settings: font, colours… Linked to `config/wezterm/local.lua` | [WezTerm](apps/wezterm.md#your-own-settings) |
| `~/.config/xdg-terminals.list` | The terminal `Super + Enter` opens | [Hyprland](session/hyprland.md#default-applications) |

A user key or rule goes in `private.lua`, not in `keybinds.lua`.

## coucou-shell's files

The other settings are files of the checkout (`~/coucou-shell` by default), linked into place: `~/.config/hypr/keybinds.lua` is `config/hyprland/hypr/keybinds.lua`. A change applies as soon as the program reloads the file.

| To change | Edit | Guide |
|---|---|---|
| Key bindings | `config/hyprland/hypr/keybinds.lua` | [Key bindings](keybindings.md) |
| Window rules, input, animations | `config/hyprland/hypr/windowrules.lua`, `hyprland.lua` | [Hyprland](session/hyprland.md) |
| Idle times | `config/hyprland/hypr/hypridle.conf` | [Hyprland](session/hyprland.md#idle) |
| What a machine does when idle | `config/hyprland/hypr/hosts/<id>.env` | [Hyprland](session/hyprland.md#per-machine-profiles) |
| The lock screen | `config/hyprland/hypr/hyprlock.conf` | [Lock screen](session/lock.md) |
| Veille | `config/hyprland/quickshell/bar/veille.json` | [Veille](bar/veille.md) |
| Roue's wheels | `config/hyprland/roue/wheels/*.toml` | [Roue](tools/roue.md#change-or-add-a-wheel) |
| Prisme's keys | `config/hyprland/prisme/keymap.conf` | [Prisme](tools/prisme.md#settings) |
| User wallpaper folders | `config/hyprland/prisme/wallpapers-extra.conf` | [Wallpapers](session/wallpapers.md#add-wallpapers) |
| The launcher | `config/fuzzel/fuzzel.ini` | [Launcher](tools/launcher.md) |
| Screenshot | `config/satty/config.toml` | [Screenshot](tools/screenshot.md#settings) |
| Liseuse's folders, keys and pages | `config/liseuse/sources.conf`, `zathurarc`, `markdown.css` | [Liseuse](tools/liseuse.md#settings) |
| Calendars | `config/hyprland/khal/config` | [Clock and agenda](bar/clock-agenda.md#calendars) |
| GTK colours and shapes | `config/nemo/theme/` | [Theme](session/theme.md#colours) |
| The equalizer's bands | `config/pipewire/50-equalizer.conf` | [Audio](session/audio.md) |

A change that adds a package or runs a script needs `cc-pkg-mng install <unit>`.

## Keep a change through an upgrade

`upgrade` and `rollback` stop when a file of the checkout has changed, and list the files. Put the changes aside, upgrade, then bring them back:

```bash
cd ~/coucou-shell
git stash
cc-pkg-mng upgrade
git stash pop
```

If the new version changed the same lines, git asks which to keep.

On the edge channel, the changes can be committed instead. Run `git pull --rebase` before `upgrade`.

## Files a unit replaced

A unit that replaces a user file (`~/.zshrc`, say) moves it to `~/.local/state/coucou-shell/backups/`. `cc-pkg-mng remove <unit>` puts it back.

## Environment variables

| Variable | Default | Effect |
|---|---|---|
| `COUCOU_SHELL_URL` | `https://github.com/lucasssoh/dotfiles.git` | What `init` clones |
| `CCPKG_STATE_DIR` | `~/.local/state/coucou-shell` | Where the manager keeps its state, backups and logs |
| `CARGO_TARGET_ROOT` | `~/.cache/dotfiles/cargo-target` | Where coucou-shell's own apps are built on edge |
| `HOST_PROFILE` | the machine's DMI product name | The [machine profile](session/hyprland.md#per-machine-profiles) to use |

## A new unit

See [writing a unit](writing-a-unit.md).
