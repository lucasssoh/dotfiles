# Your settings

Where every setting lives, which files are yours alone, and what an upgrade does to your changes.

There are two kinds of files:

- **Files that are yours.** They exist on your machine only. coucou-shell creates some of them with defaults, then never replaces them.
- **Files of coucou-shell.** They live in the checkout (`~/coucou-shell` by default) and are linked into place. You can edit them; an upgrade then has to deal with your edits.

## Files that are yours

Nothing here is committed, and no upgrade, install or rollback touches these files. A missing file means the defaults.

| File | Sets | Written by | Guide |
|---|---|---|---|
| `~/.config/hypr/private.lua` | Your own window rules and keys, loaded last | you | [Hyprland](session/hyprland.md#your-own-rules-and-keys) |
| `~/.config/hypr/bar-position.json` | The bar at the top or at the bottom | you | [The bar](bar/index.md#position) |
| `~/.config/hypr/bar-island.json` | The centre island's colour, opacity, blur and text | you | [Centre island](bar/island.md#its-look) |
| `~/.config/hypr/monitor-layout.json` | Where your screens sit | you | [Displays](session/displays.md#where-they-sit) |
| `~/.config/hypr/scale.json` | The scale of each screen | you | [Displays](session/displays.md#scale) |
| `~/.config/hypr/display-layout.json` | Which screens are on | the display wheel | [Displays](session/displays.md#which-screens-are-on) |
| `~/.config/hypr/hdr-state.json` | HDR or SDR, for each screen | Balise | [Displays](session/displays.md#hdr) |
| `~/.config/hypr/wallpaper-playlist.json` | Your wallpaper, or your slideshow | Prisme | [Wallpapers](session/wallpapers.md) |
| `~/.config/xdg-terminals.list` | The terminal `Super + Enter` opens | you | [Hyprland](session/hyprland.md#default-applications) |
| `~/.config/programme/settings.json` | Programme's settings | Programme | [Programme](bar/programme.md) |
| `~/.local/state/bar-equalizer.json` | Your equalizer curves, by app | the mixer | [Mixer](bar/mixer.md#equalizer) |
| A wallpaper folder of your own | Your wallpapers, once listed in `wallpapers-extra.conf` | you | [Wallpapers](session/wallpapers.md#add-your-own) |
| `~/Livres/` | Your books | you | [Liseuse](tools/liseuse.md) |

Edit the files written by "you" in any text editor. The others are written by the tool named: change the setting there, not in the file.

`~/Images/Wallpapers` is not yours: it's rebuilt from the wallpaper folders, and a file placed there by hand is deleted.

`~/.config/hypr/` is a link into the checkout, so these files sit in `config/hyprland/hypr/` too. Git ignores them.

## Files of coucou-shell

Everything else is a file of the checkout, linked into place: `~/.config/hypr/keybinds.lua` is `config/hyprland/hypr/keybinds.lua`. Edit either, it's the same file. The change takes effect as soon as the program reloads it.

| To change | Edit | Guide |
|---|---|---|
| Key bindings | `config/hyprland/hypr/keybinds.lua` | [Key bindings](keybindings.md) |
| Window rules, input, animations | `config/hyprland/hypr/windowrules.lua`, `hyprland.lua` | [Hyprland](session/hyprland.md) |
| Idle times | `config/hyprland/hypr/hypridle.conf` | [Hyprland](session/hyprland.md#idle) |
| What a machine may do when idle | `config/hyprland/hypr/hosts/<id>.env` | [Hyprland](session/hyprland.md#per-machine-profiles) |
| The lock screen | `config/hyprland/hypr/hyprlock.conf` | [Lock screen](session/lock.md) |
| Veille | `config/hyprland/quickshell/bar/veille.json` | [Veille](bar/veille.md) |
| Roue's wheels | `config/hyprland/roue/wheels/*.toml` | [Roue](tools/roue.md#change-a-wheel-or-make-your-own) |
| Prisme's keys, and your wallpaper folders | `config/hyprland/prisme/*.conf` | [Prisme](tools/prisme.md#settings), [wallpapers](session/wallpapers.md#add-your-own) |
| The launcher | `config/fuzzel/fuzzel.ini` | [Launcher](tools/launcher.md) |
| Screenshot | `config/satty/config.toml` | [Screenshot](tools/screenshot.md#settings) |
| Liseuse's folders, keys and pages | `config/liseuse/sources.conf`, `zathurarc`, `markdown.css` | [Liseuse](tools/liseuse.md) |
| Calendars | `config/hyprland/khal/config` | [Clock and agenda](bar/clock-agenda.md#calendars) |
| GTK colours and shapes | `config/nemo/theme/` | [Theme](session/theme.md#colours) |
| The equalizer's bands | `config/pipewire/50-equalizer.conf` | [Audio](session/audio.md) |

### What an upgrade does to your edits

After an edit, `cc-pkg-mng status` shows the unit as *changed since installed*.

`upgrade` and `rollback` stop when the checkout has uncommitted changes, and tell you which files. Put your edits aside, upgrade, then bring them back:

```bash
cd ~/coucou-shell
git stash
cc-pkg-mng upgrade
git stash pop
```

If the new version changed the same lines, git asks you to choose.

- **On stable**, don't commit your edits: each release is checked out on its own, and a commit of yours stays behind on the previous one.
- **On edge**, you can commit them instead. `upgrade` then stops when the branch has moved on without them: run `git pull --rebase` first.

To keep a setting through every upgrade without thinking about it, prefer a file that is yours: a key or a rule goes in `private.lua` rather than in `keybinds.lua`.

Some changes need more than a reload, like a new package or a hook. For those, run `cc-pkg-mng install <unit>`.

## Files a unit replaced

If a unit replaces a file you already had (your own `~/.zshrc`, say), your file goes to `~/.local/state/coucou-shell/backups/` first. `cc-pkg-mng remove <unit>` puts it back.

## Environment variables

| Variable | Default | Effect |
|---|---|---|
| `COUCOU_SHELL_URL` | `https://github.com/lucasssoh/dotfiles.git` | What `init` clones |
| `CCPKG_STATE_DIR` | `~/.local/state/coucou-shell` | Where the manager keeps its state, backups and logs |
| `CARGO_TARGET_ROOT` | `~/.cache/dotfiles/cargo-target` | Where coucou-shell's own apps are built on edge |
| `HOST_PROFILE` | taken from the machine's DMI product name | Forces a machine profile. See [per-machine profiles](session/hyprland.md#per-machine-profiles) |

## A unit of your own

See [writing a unit](writing-a-unit.md).
