# Modules

Each directory under `config/` that contains an `install.sh` is a module. The list, its order and its constraints live in [`scripts/lib/modules.sh`](../scripts/lib/modules.sh); see [configuration.md](configuration.md#the-module-registry) for how to add one.

Every module can be run on its own:

```bash
bash config/nvim/install.sh
```

Run that way it may install packages and will ask for sudo if something is missing. Run through `cc-pkg-mng update`, it never will — see [cc-pkg-mng.md](cc-pkg-mng.md#privilege-scope).

## Order

The order is part of the contract, not an accident:

```
fonts  bash  ccpkg  ccnote  ccslide  tmux  wezterm  nvim  pipewire  wireplumber
mangohud  nemo  fuzzel  fastfetch  firefox  brave  mpv  liseuse  boot/plymouth  hyprland
```

A module name may carry **one level of nesting**. `config/boot/` groups the two pieces that own the screen before the desktop exists — the splash and the greeter — because that is one subject, and splitting it across a flat list next to `mpv` lost it. A grouping directory has no `install.sh` of its own; `registry_validate` checks both depths, and also refuses a directory under `config/` that is neither a module nor a group, since nothing would ever run it.

| Constraint | Why |
|---|---|
| `ccpkg`, `ccnote`, `ccslide` after `bash` | `.zshrc` sources `~/.config/ccnote/ccnote.zsh` and `~/.config/ccslide/ccslide.zsh`, and `~/.local/bin` reaches `PATH` through `.bashrc` |
| `liseuse` after `fuzzel` | its picker *is* fuzzel |
| `pipewire` before `wireplumber` | the equalizer is a filter chain loaded by the pipewire daemon, and `wireplumber` ends by restarting the audio stack — the other order links the chain, then restarts the stack underneath it |
| `hyprland` last | the desktop assembles everything above it |

Two modules are **opt-in** — never part of a default run, and must be named explicitly:

| Module | Status |
|---|---|
| `boot/login` | Rewrites system login (ly, with greetd+tuigreet kept as the fallback) and prompts interactively |
| `kde` | Not used on this machine. Its Reversal icon theme upstream is a 404 as of 2026-09-16; whoever re-enables it needs to pick a replacement first |

---

## Shell and terminal

### `bash`

| | |
|---|---|
| Installs | `fzf ripgrep make gcc zsh zoxide`, plus `fd-find` / `fd` depending on the distro |
| Links | `~/.bashrc`, `~/.zshrc`, `~/.bash_aliases`, `~/.config/bash/prompt.zsh` |

Also clones `zsh-autosuggestions` and `zsh-syntax-highlighting` into `~/.zsh`, and switches the login shell to zsh if it is not already. On Debian/Ubuntu, `zoxide` has no usable package and is fetched from the upstream installer instead; the script downloads it first and runs it second, because a piped `curl | sh` hides a download failure behind `sh` exiting 0 on empty input.

### `tmux`

Installs `tmux wl-clipboard`, links `~/.tmux.conf`.

### `wezterm`

Installs `wezterm`, links `~/.wezterm.lua` and `~/.config/wezterm/wezterm.lua`. Needs a third-party repo — the `wezfurlong/wezterm-nightly` copr on Fedora, `apt.fury.io/wez` on Debian — which is only added when wezterm is genuinely absent.

### `nvim`

Installs `neovim`, links `init.lua`, `lua/`, `ftplugin/` and `colors/` into `~/.config/nvim/`. The directories are linked whole, so a new file in `config/nvim/lua/` is live without re-running anything.

### `ccnote` · `ccslide`

Two small shell tools, each a Python script plus a zsh wrapper linked into `~/.config/<name>/`. `ccslide` renders Markdown slides through `mdp`; when no package provides it, the module builds it from source, which is the only reason it installs `git make gcc` and the ncurses headers.

### `ccpkg`

Links `bin/cc-pkg-mng` into `~/.local/bin`. A symlink, never a copy — the link points into the repo, so `git pull` updates the command with nothing to rebuild. Warns if the name resolves somewhere other than `~/.local/bin`.

---

## Desktop

### `hyprland`

The largest module by a wide margin, and the one that does the heavy lifting.

| | |
|---|---|
| Installs | ~61 packages, distro-dependent, plus three coprs on Fedora (`lionheartp/Hyprland`, `errornointernet/quickshell`, `mineiro/satty`) |
| Builds | `balise`, `prisme` + `wallpaper-filter`, `roue` — from the sources in this repo, skipping any crate that has not changed |
| Links | `hypr`, `waybar`, `quickshell`, `rofi`, `balise`, `prisme`, `roue`, `hyprlock`, `scripts`, `khal`, `theme` into `~/.config/` |
| Services | Four `systemd --user` units: `balise`, `wallpaper-slideshow`, `slideshow-fullscreen-guard`, `workspace-dashboard` |

It also downloads four icon/mono fonts when absent (JetBrains Mono Nerd Font, GoogleSansCode Nerd Font Mono, Phosphor Icons, Lucide Icons — the last two resolved from the npm registry), and builds the Comix Cursors theme from upstream SVGs when `~/.icons/ComixCursors-White` does not exist.

Config directories are linked, not copied: editing a file in the repo changes the live config immediately. `hyprctl reload` picks up the Lua; quickshell watches its own QML and reloads itself.

`--reset` wipes the previously-linked config directories before relinking.

Each copr is enabled only when the package it provides is actually missing.

### The bar's drawers

The bar is quickshell, linked by `hyprland` and living in [`config/hyprland/quickshell/bar/`](../config/hyprland/quickshell/bar/). Most of it is a row of pills, but four panels drop out of the **TOOLS** island on the right, and they are the part worth describing because they are where the desktop's settings actually live.

| Drawer | Opened by | What it holds |
|---|---|---|
| Notification centre | the bell | clock, do-not-disturb, MPRIS transport with a seek bar, history, clear all |
| [Balise](../config/hyprland/quickshell/bar/modules/balise/) | its own button | WiFi / Bluetooth / Ethernet with real device lists, night mode, HDR, dark mode, screenshot |
| [Power](../config/hyprland/quickshell/bar/modules/power/) | the battery pill | time remaining, charge limit, power profile, and a charge curve |
| [Mixer](../config/hyprland/quickshell/bar/modules/mixer/) | either audio pill | output and input levels with live meters, every device listed under each, per-application volume, and a page per application for its equalizer |

Two more drawers hang off the **central** island — the sleep clock (`veille`) and the keybindings sheet — but those two stack, while the four above are **mutually exclusive**: each one's `togglePanel` closes the other three before opening. They also all close on the same Hyprland events the keybindings sheet watches, which is how a layer-shell surface that never receives a focus-loss event still dismisses on an outside click.

Two of the four cost the TOOLS island nothing. Balise and the notification centre have a button apiece — that is all `BaliseButton` and `NotificationBell` are — but Power and the Mixer are opened by pills that were already in the row for another purpose: the battery readout and the two audio icons. Clicking the thing you want the detail of is the same affordance either way, and for those two it needed no new pixel.

Each drawer is an entry in `DrawerIsland`'s `drawerItems` and satisfies a three-line contract: a `drawerOpen` bound from outside, an `implicitHeight` it computes itself, and a `Behavior on height` matching the island's reveal duration. The island owns everything else — the stretch, the staged fade, the clipping.

**They cost nothing while shut**, and that is deliberate in each case. Power's `GetHistory` calls are gated on the panel being open. The mixer's device bindings and both its level meters are too — a `PwNodePeakMonitor` is not a property read, it opens a real capture stream. Closing a drawer is what takes it back to zero.

#### The mixer

It replaced the last place in the bar where a control shelled out to an external UI for something the process already had live handles on. Picking an output ran `audio.sh roue-gen && roue audio-output` — a script that regenerated a wheel config from `pactl list sinks`, then launched a separate process to draw it. Per-application volume had no in-bar path at all; right click opened pavucontrol. Both are now property writes on `Quickshell.Services.Pipewire`. Right click still opens pavucontrol, kept as the escape hatch for card profiles and per-stream moves the drawer does not do.

**Dead entries are filtered out.** With nothing plugged in, this laptop enumerates four sinks of which three are unselectable (HDMI ports reporting "not available") and two sources of which one is (the analog headset mic). Selecting a dead one is not merely ineffective — wireplumber accepts the request, refuses it, and writes the old device straight back, so the tick visibly fails to move. Pipewire cannot answer the question, since availability belongs to the device *route*, one level below `PwNode`; so `MixerState` makes one `pactl` read and hides them. A row that does nothing when clicked is worse than no row, and with the filter in place a single-output machine correctly lists nothing at all — the master row above already names the only device there is.

The devices are simply **listed** under each master, not folded behind a chevron. They were, and unfolding one changed the drawer's height, which the drawer then animated: the panel moved every time anyone went looking for a device. The same reasoning retired the preset picker below. The only chevron left in the drawer is on an application row, where it means "there is a page behind this" — so it points right, the way a page is.

**A newly connected device takes the sound**, in both directions when it has an input worth using. This has to live here rather than in wireplumber, and the reason is caused by the drawer itself: WirePlumber picks the default by `priority.session` only while nothing has been *configured*, and the moment anything writes `default.configured.audio.sink` the choice is pinned. `pactl set-default-sink` writes it, and so does choosing an output by hand — so the act of ever picking a device is what switches the automatic behaviour off. The rule is narrow on purpose: follow only a device that has just **joined the selectable set**, which covers both shapes a connection takes, a new node (USB, Bluetooth) and a port going from unavailable to available (jack, HDMI). A device leaving needs nothing; wireplumber falls back on its own.

**The equalizer is per application, on a page of its own.** The chevron on an application's row opens it — the same navigation Balise uses for a WiFi network or a bluetooth device, and for the same reason: five faders, a preset list and a switch came to about 260 px, which on the home page sat between INPUT and PLAYING and pushed the list of what is actually playing off the bottom of the drawer, for a control adjusted once per application and then left for weeks. The row keeps level and mute, and shows an `EQ` badge while that application is going through a chain.

The choice is filed under the **application name**, not a node id, so it survives the application closing and the bar restarting. A film in mpv can be equalized while a video in the browser is left exactly alone, which was the point: the concern was never "how do I equalize everything", it was "how do I not equalize a YouTube video".

**Ten presets**, listed under the faders and always on screen. There were twenty-eight, which was too many to choose from and too many to draw — the page had to hide them behind a chevron to fit, and unfolding it changed the page height by a couple of hundred pixels, which the drawer then animated. Ten fit, so the list is simply there and the page never changes height. What went were the near-duplicates and the raw tone-shapers, which a fader does better than a preset: pulling the 12k band down *is* "treble cut", in one gesture on a control already on screen. What stayed is one entry per shape the curve can usefully take, including Vocal — the one that matters for a series, where the dialogue needs lifting out of the effects.

They are written for five bands rather than transposed from a ten-band table, because dropping every other entry of one lands the wrong gain on a shelf covering an octave more than the peak it replaced. Flat is the first chip and doubles as the reset, so there is no separate reset link either. Moving any fader clears the label to **Custom**: the curve is no longer Rock, it is Rock with one band pulled, and calling it Rock would be the page lying about what you hear.

Switching an application off moves its stream back out of the chain rather than zeroing its bands. Zeroing would be one write instead of a move, and it would leave ten biquads running on every sample to multiply it by one — half a percent of a core, indefinitely, for no audible difference. Emptied, the chain suspends.

The curves reach pipewire through **one resident `pw-cli`** fed by its stdin, because nothing in `Quickshell.Services.Pipewire` can write a node's Props and a filter's control ports are Props. Both arrangements were measured on this machine:

| | per parameter write |
|---|---|
| a fresh `pw-cli` each time | 8 ms |
| one resident `pw-cli`, fed by a pipe | 83 µs |

Two orders of magnitude, and it is what makes a band audible *while* its fader is dragged rather than only when it is released. At rest it costs nothing measurable: 0 ms of CPU over 3 s idle, 7.5 MB resident, flat across 600 writes. **The one trap**: if that process's stdin reaches EOF it does not exit, it spins — measured at 1 s of CPU in 10 s. `stdinEnabled` is set once, declaratively, and must never be turned off to "tidy up".

The parameter names are identical in every slot — they are scoped to their own graph — so only the target node id changes between them, and a slot that changes hands gets the new occupant's whole curve re-pushed.

Profiles persist to `~/.local/state/bar-equalizer.json` — `state`, not the `~/.cache` the wallpaper tint uses, because a cache is something a daemon can regenerate and a curve dialled in by ear is not.

### `pipewire`

Installs `pipewire pipewire-utils` and links one file: [`50-equalizer.conf`](../config/pipewire/50-equalizer.conf), **four** independent five-band filter chains loaded by the pipewire daemon itself. **Restarts the audio stack at the end**, because `pipewire.conf.d` is read at startup only.

It is a module of its own rather than a file inside `wireplumber` because the two configure different daemons, and because this one is a hard dependency of the bar: the mixer drawer routes applications into the chains it creates, and drives their curves through `pw-cli`.

`pw-cli` is why `pipewire-utils` is named here **unconditionally**. `wireplumber`'s own module asks for it too, but behind `if ! command -v wireplumber`, so on a machine that already had wireplumber the whole line was skipped — which is how this one ran for months with no `pw-cli` and no `pw-dump`, and took `bt-audio-switch.service` down with it: that script needs `pw-dump` and had been exiting after 6 ms ever since. `pkg_ensure` queries before it installs, so naming it in both places costs nothing.

Each chain is ten biquads — five bands (60 / 250 / 1k / 4k / 12k) across two channels — rather than one `param_eq`, which chains them more efficiently but reads its curve from a `config` section once at load. The individual `bq_*` filters expose `Freq`, `Q` and `Gain` as **control ports**, and a control port can be written while the graph runs. That is the whole requirement: the curve is driven from a page with faders on it.

**Why four, and why pre-declared.** The equalizer is per application, so two applications playing at once with different curves need two chains — a chain is a sink, and a stream is in one sink or another. Creating them on demand does work: `load-module libpipewire-module-filter-chain` typed into the resident `pw-cli` is loaded into the *daemon*, so it outlives the client that asked for it. That is exactly the problem. Destroying one again needs `unload-module` and a pw-cli *variable* naming the module, recoverable only by parsing pw-cli's own output back out of the pipe — get it wrong, or restart the bar, and chains accumulate in the daemon with nothing able to name them again. Measured once by accident, with a test chain still present after the process that made it had exited. Four fixed slots have no lifecycle at all; the application's page says so when they are all taken.

Unused slots cost nothing: with no stream routed in, a chain suspends and stops being scheduled. Measured with `pw-top` on one chain carrying one stream, 1024-frame quantum at 48 kHz (21.3 ms of audio):

| node | BUSY per quantum |
|---|---|
| the ten biquads | 18–26 µs |
| output stream + resampling | 72–84 µs |

≈ 0.5 % of one core, per chain actually carrying audio.

**The `eq_slot_` / `eq_out_` prefixes are load-bearing.** `MixerState.qml` identifies everything belonging to the equalizer by them, and uses that to keep the chains out of the output list *and* out of the "a device was just connected" rule. Without it a chain is an `Audio/Sink` like any other: found during development when a test chain appeared and the bar made it the default output within the second — which means the chain feeding itself. Any node added to that file must carry one of the two prefixes.

### `wireplumber`

Installs `wireplumber pipewire-utils` and links five files: the Bluetooth policy drop-ins, a `bt-audio-switch.sh` script, and its `systemd --user` unit. **Restarts `wireplumber`, `pipewire` and `pipewire-pulse` at the end**, which cuts audio for a moment — one of the two modules with a visible side effect on a running session.

One of its drop-ins is dead weight: `10-bluetooth-policy.conf` sets `wireplumber.policy.switch-on-connect`, a 0.4-era key that does not appear in `wpctl settings` on 0.5.14 and does nothing. Following a newly connected device is handled in the bar instead — see [the mixer](#the-bars-drawers) for why it has to be.

### `nemo`

Installs `nemo nemo-fileroller xdg-desktop-portal-gtk`, sets the file-manager MIME defaults, writes a D-Bus service file and restarts the xdg portals.

Also carries the GTK3 theming, linked to `~/.config/gtk-3.0/` (`settings.ini` + `gtk.css`). Nemo is GTK3, not Qt, so `qt6ct` never sees it. Two separate things live there: `settings.ini` is what makes it *dark* — the session asked for `gtk-theme='Adwaita-dark'`, which is not a GTK3 theme name, so GTK3 fell back to light Adwaita — and `gtk.css` is what makes it *ours*, redefining Adwaita's colour names with the tokens from `quickshell/bar/theme/{Ink,Surfaces}.qml`. The install also rewrites that one stale `gtk-theme` value in dconf, because the portal serves it to GTK3 ahead of `settings.ini`. The link reaches every GTK3 app, which here means Nemo and the GTK file-chooser portal this module installs.

### `fuzzel`

Installs `fuzzel`, links `~/.config/fuzzel/fuzzel.ini`. This is `Super + Space`, and also the picker `liseuse` is built on.

### `fonts`

Installs no package. Downloads JetBrains Mono, Iosevka and Cascadia Code Nerd Fonts plus MiSans Latin into `~/.local/share/fonts/`, each guarded by an `fc-list` check so nothing is re-fetched. Links the fontconfig rule, then applies the UI font through `gsettings` and `kwriteconfig6`. `fc-cache` runs only if something was actually added.

### `boot/plymouth`

The boot splash, from GRUB's hand-off to the greeter: the word mark breathes on black and one thin bar fills near the bottom edge.

It exists because that stretch of the boot used to draw *nothing*. The cause was not the theme but a missing package: `plymouth-graphics-libs` owns `/usr/lib64/plymouth/renderers/{drm,frame-buffer}.so`, which is every renderer Plymouth has, and without one the daemon cannot put a pixel on a screen whatever theme is selected. The selected theme was `text`, which draws nothing under `rhgb quiet` anyway. On an OLED panel the result was several seconds of a laptop that looked switched off.

**The boot splash never appeared for weeks, and it came down to a comment.** Fedora ships `/etc/plymouth/plymouthd.conf` with its example commented out — `#Theme=fade-in` — and `plymouth-set-default-theme` reads the theme back out with an *unanchored* regex and an empty output separator:

```awk
BEGIN { FS="[=[:space:]]+"; ORS="" }
$1 ~ /Theme/ { print $2 }
```

`#Theme` matches `/Theme/`, so with `Theme=coucou` set the file reads back as `fade-incoucou`. No such theme exists, so it falls through to `plymouthd.defaults` (`bgrt`, not installed), then to the `default.plymouth` symlink (which that same tool deletes), and lands on its last resort: **`text`**.

`plymouth-populate-initrd` asks exactly that command which theme to bake in. It got `text`, and dutifully baked in the text theme and `text.so` — while `plymouthd` at boot read `Theme=coucou` from the same file with its own, correct parser, found no such theme in the initramfs, and fell back to the text splash, which under `quiet` draws nothing. The shutdown splash worked the whole time, because by then the real root is mounted and the theme is simply there. So the module deletes the commented line: it is an example nobody needs and a landmine for a parser that cannot tell a comment from a setting. The module also declares the theme files and `script.so` to dracut through `install_items`, as a backstop — not because that is the fix, but because the failure was invisible, and stating the dependency outright means the splash no longer rests on a chain that answered wrongly for months without a single error message.

**A new kernel keeps the splash on its own, and is checked anyway.** Nothing about the fix is tied to a kernel: `/etc/dracut.conf.d/90-coucou-splash.conf` is read by every `dracut` run, and `kernel-install`'s `50-dracut.install` invokes a plain `dracut -f` with no `--no-conf` or `--confdir`, so a kernel installed by `dnf update` picks the theme up unassisted. What was missing was never the building — it was the noticing, since dracut runs `plymouth-populate-initrd` with `2> /dev/null` and that script silently baked in the wrong theme for weeks. So the module installs `/etc/kernel/install.d/99-coucou-splash.install`, numbered after the dracut plugin: it builds nothing, it reads the initramfs that was just produced and reports into the output of the very `dnf` transaction that produced it. It also re-checks that `plymouth-set-default-theme` still answers `coucou`, because a plymouth package update restoring the stock `plymouthd.conf` would reintroduce the commented-`Theme=` regression, and the symptom of that gives no clue at all. It always exits 0: a check has no business aborting a kernel install. `install.sh` verifies every `/boot/initramfs-*.img` for the same reason — the older GRUB entry is the one that matters on the day something has already gone wrong.

**The rebuild decision is a stamp, not a diff of the current run**, and that distinction cost a black boot. The old logic skipped `dracut` when nothing had changed *during this run*. `preview.sh` calls the installer with `--no-initramfs`; that run installed the packages, deployed the theme and selected it, consuming every "changed" signal. The next full run saw four zeroes and concluded the initramfs was current — when dracut had never run once. The boot said so precisely:

```
Trying to load /etc/plymouth/plymouthd.conf
key file has comments but no groups
failed to load /etc/plymouth/plymouthd.conf
```

That is Fedora's pristine file, the one where `[Daemon]` is commented out, still inside an initramfs built before the theme existed. With no `Theme=` to read and no `default.plymouth` symlink to fall back on — `plymouth-set-default-theme` deletes it — plymouthd loaded the `text` splash, which under `quiet` draws nothing. The renderer was never implicated: the same log shows `drm.so` opening card1 and creating a 1920x1200 head half a second earlier. So the question asked is now "does the initramfs match what we would build now?", answered by a stamp that only a *successful* dracut writes, and the build is verified afterwards with `lsinitrd` — both that the theme is in there and that the copied `plymouthd.conf` still has a `Theme=` line. A build that fails either check writes no stamp and fails the module, so the next run retries instead of believing itself done.

The module installs the renderers, the script plugin and the label plugin, deploys `theme/` to `/usr/share/plymouth/themes/coucou`, selects it, and rebuilds the initramfs — the splash starts before `/` is mounted, so the theme rides inside it. `--regenerate-all` covers every installed kernel, not just the running one: the second GRUB entry is the one booted when something is already wrong. The rebuild is the only slow step, so it is skipped unless something that ends up inside the initramfs actually changed. In user scope the whole module defers, being system-wide.

Plymouth's script plugin has no drawing primitives — no text, no rectangle, no rounded corner — so every pixel is a PNG. [`make-assets.py`](../config/boot/plymouth/make-assets.py) generates them (the word in JetBrains Mono Light, the bar, the password dots) and the results are committed beside it, so a fresh machine needs no font to boot prettily; re-run it by hand, with `--width` for a panel that is not 1920 wide. The face is resolved through `fc-match` rather than a hardcoded path, and checked against what came back — fc-match answers with its nearest match and never fails, so a missing family would otherwise ship a word mark quietly set in the wrong typeface. One family runs through the whole splash: the mark, the status line, and the console the greeter draws on. The word depends on which way the machine is going. `Plymouth.GetMode()` answers `boot`, `shutdown`, `reboot` and a few update modes; shutdown and reboot load `logo-bye.png` (**byebye**) instead, because greeting someone on the way out reads backwards — the thing that prompted it was noticing "coucou" on a power-off. Reboot counts as leaving, since the boot that follows says coucou on its own. The update modes keep the greeting: the machine is neither arriving nor leaving there, and a third word for a screen seen twice a year is more vocabulary than a splash can carry. The load is guarded on the image rather than assumed — a missing `logo-bye.png` would make every sprite downstream NULL, and that would only ever show on a shutdown.

This is also the half of the theme that has been *seen* working: the shutdown splash reads the theme from the real root rather than the initramfs, so it came up correctly while the boot splash was still falling back to text. That is what localised the boot failure to the initramfs and nothing else.

[`coucou.script`](../config/boot/plymouth/theme/coucou.script) owns placement and motion: a cosine breath counted in frames (the language has no clock), and a bar that eases towards Plymouth's progress estimate and never runs backwards. The passphrase prompt draws its bullets as dots rather than glyphs, since no font is guaranteed to exist inside the initramfs.

Under the bar runs the boot log, one line at a time. Nothing feeds that for free: systemd does not talk to Plymouth at all — on Fedora 44 the only shipped binary calling `plymouth_send_msg` is `systemd-storagetm` — and the `update --status` channel carries just the three messages Plymouth's own switch-root and read-write units send. So the module installs [`status-feed.sh`](../config/boot/plymouth/status-feed.sh) as `coucou-splash-status.service`, which polls systemd's job list five times a second and pushes the most recently started running unit. It polls rather than subscribing because the event-driven route is a D-Bus match, and the system bus is one of the services it would be narrating. It lives in `/etc` and `/usr/local`, not in the initramfs, so changing it costs no dracut run — and the initramfs phase, which it is too late for, shows Plymouth's own messages alone.

**One splash, not two.** Left alone, the splash appears at ~1.07s on simpledrm, the screen goes black for ~1.8s while i915 claims the panel, then it comes back — `card0` is removed at 01.806 and `card1` arrives at 03.573, and between them there is no display device for any theme to draw on. Upstream describes the same thing in the commit that added Fedora's `UseSimpledrmNoLuks` default: *"the unlock screen will briefly show and then the screen goes black while the native GPU driver loads leading to a jarring experience"*. The module sets `UseSimpledrm=0`, which `load_settings()` reads *before* `UseSimpledrmNoLuks` and which short-circuits it, so this beats the distribution default rather than fighting it. The trade is a 0.7s flash at 1.1s exchanged for nothing until ~3.6s; both reach a stable splash at the same moment, but the machine now goes from black to the word once and stays there. The file is copied into the initramfs, so its hash is part of the rebuild stamp.

**No progress bar on the way out.** On shutdown and reboot the bar is hidden and the word is the whole splash. Plymouth's estimate is elapsed time over the duration of the previous run of the same operation: a fair guess for a boot, which does roughly the same work every time, and a poor one for a shutdown, whose length is set by whatever is still holding a mount or a session — exactly the part that varies. A bar there fills at a rate unrelated to what is happening and either finishes early or hangs near the end. It is a decoration shaped like a measurement, which is worse than no measurement.

**Resolutions.** Placement is fractional — the word at 0.50 of the height, the bar at 0.895, the log at 0.935, all centred horizontally on the screen's own width — so the composition holds at any resolution and any aspect ratio, and `SetDisplayHotplugFunction` re-lays it out if the mode changes mid-boot. The assets are scaled by `layout.k`, the panel's width over `REF_WIDTH`, with a snap to exactly 1 so the reference panel is never resampled. Two things do not follow from that:

- **Sharpness off the reference width.** Scaling goes through Plymouth's `Image.Scale`, not through `make-assets.py`'s. The layout stays right, the word mark just gets softer than it needs to be. `install.sh` reads the connected panel out of `/sys/class/drm/*/status` and says so when it differs, with the `make-assets.py --width` line to fix it.
- **Text.** A font description is a string and this language cannot build one from a number, so the status line's size comes off a four-rung ladder (`STATUS_FONT*` / `STATUS_K_*`) instead of scaling continuously. `simulate.py` reads the same ladder and applies it, so `--width 3840 --height 2160` is a real preview of a 4K panel.

**Two screens.** Plymouth does not lay displays out side by side, and this is the part that is easy to get backwards. `update_displays()` in `script-lib-sprite.c` builds one virtual canvas as wide as the widest display and as tall as the tallest, *centres* every display inside it, and draws every sprite on every display at `sprite.x - display.x`. Two screens are not two canvases; they are two centred windows onto the same one, and duplicating sprites per head would double-draw rather than help.

So `measure_screen()` lays out inside the intersection of those windows, which — since they are all centred — is exactly the smallest width by the smallest height, centred on the canvas. `Window.GetWidth(i)` returns display *i*'s width and NULL past the end, which is the only way to count them; with no argument it returns the canvas. Both forms are used. The consequence worth knowing: the splash is sized for the *smallest* attached display, so it is guaranteed to fit on every screen and looks correspondingly smaller on a large one. `simulate.py --heads 1920x1200,3840x2160` renders what each screen actually shows, stacked, so this is checkable without owning a second monitor.

One ordering dependency this creates: `plymouth-plugin-label` has to be installed *before* dracut runs, or `plymouth-populate-initrd` finds no `label-freetype.so` to copy and skips the font symlink with it — leaving the status line blank at boot and nowhere else. `install.sh` does the packages first for that reason.

[`simulate.py`](../config/boot/plymouth/simulate.py) renders the motion to a video and plays it full screen — the fast loop for judging the pulse and the easing, since it costs nothing but a few seconds of CPU. It composites the real PNGs and reads every constant out of `coucou.script` rather than carrying its own copy, so it cannot drift from the theme; what it does *not* reproduce is Plymouth's scaler, its timing under load, or the panel itself. The boot log is faked from a list of plausible unit names, and `--print-schedule` hands that same list to `preview.sh --status`, so the fake boot log is defined once rather than twice.

**The status line's font** is `JetBrains Mono`, and the family string is doing two jobs. On a booted system the plugin is `label-pango`, which honours the family. Inside the initramfs it is `label-freetype`, which ignores the family entirely and keeps two faces, a default and a monospace one, choosing between them by substring — `strstr(font, "Mono")`. So naming JetBrains Mono is also what selects the monospace slot at boot; rename it to something without "Mono" in it and the boot silently falls back to the proportional face while the preview keeps looking right.

That slot is filled by `fc-match monospace` run **as root at dracut time**, which is why the module installs a system-wide `/etc/fonts/conf.d/70-mono-font.conf` ([`mono-fontconfig.conf`](../config/boot/plymouth/mono-fontconfig.conf)) rather than a user rule: a user rule cannot reach root's query, and an environment override passed to one dracut run would be undone by the next kernel update rebuilding the initramfs on its own. It is numbered **55**, and the numbering is the whole mechanism — running backwards from the obvious guess. `mode="prepend"` inserts before the element the test *matched*, and every package rule tests the same generic `monospace`, so a rule running later lands closer to `monospace` and further from the head of the list: the earliest rule wins. Shipped at 70 it was loaded, reported active by `fc-conflist`, and changed nothing — `FC_DEBUG=1 fc-match monospace` showed JetBrains Mono sitting in last place. 55 puts it after `50-user.conf`, so a per-user file can still override, and before `56-google-noto-sans-mono-vf.conf`, which is the one to beat. (`config/fonts/70-ui-font.conf` wins for a different reason: per-user files are all pulled in at position 50.) Deliberate side effect: this changes the generic monospace default for the whole machine, so the terminal and the editor — which name JetBrains Mono explicitly — stop being contradicted by it. `install.sh` checks the *result* (`fc-match` as root) rather than just the file copy, and counts the rule as an initramfs-relevant change even though it is not copied into one: it decides which font file is.

The size is **points at 96 dpi** in both plugins, not pixels — `FT_Set_Char_Size(face, points * 64, 0, 96, 0)` — so 15 is 20px on screen. A `px` suffix would switch to literal pixels; nothing uses it. The simulator converts before handing the size to PIL, and prints the family it resolved, so a mismatch with the boot shows up rather than hiding.

[`preview.sh`](../config/boot/plymouth/preview.sh) shows the splash without rebooting — **on hardware where that is possible, which this laptop is not**. Plymouth renders to whatever DRM device it can open; at boot that is simpledrm on `/dev/dri/card0`, and once i915 claims the panel as `card1` simpledrm is released, so after boot card0 is gone. A hand-started `plymouthd` then opens no device, cannot start a graphical splash, and falls back to the text one — indistinguishable on screen from a theme that draws nothing. The script now reads the daemon log for exactly that failure and says so, instead of letting the tool's limit be blamed on the theme. When it fires, the real diagnosis is a real boot: `plymouth.debug` on the kernel command line writes `/var/log/plymouth-debug.log`.

Mechanically it works like this: it deploys the theme, starts `plymouthd` on a spare VT, switches to it and switches back — with a detached watchdog that returns the screen even if the script is killed. `--sweep` drives the bar through a known 0→100 ramp, `--password` exercises the prompt.

---

## Applications

### `firefox`

Installs `firefox`, links `~/.config/environment.d/firefox.conf` (native Wayland). Also writes a system policy to `/etc/firefox/policies/` — the only root-owned step, deferred in user scope.

### `brave`

Adds Brave's own rpm repo and installs `brave-browser`. Rather than a config file, it generates a **user `.desktop` override** in `~/.local/share/applications/`, injecting the flags from [`config/brave/brave-flags.conf`](../config/brave/brave-flags.conf) into every `Exec=` line, field codes preserved. Brave's launcher reads no flags file of its own, so this is the mechanism that works.

The module verifies each `--enable-features` name against the installed binary and warns if one is unknown — a renamed Chromium feature is otherwise silently ignored, with no error and no effect.

### `mpv` · `mangohud` · `fastfetch`

One package and one config link each: `~/.config/mpv/mpv.conf`, `~/.config/MangoHud/MangoHud.conf`, `~/.config/fastfetch/config.jsonc` plus its image.

### `liseuse`

Installs the zathura stack (`zathura`, `zathura-pdf-mupdf`, `zathura-cb`, `zathura-djvu`, mupdf, libnotify), links `zathurarc`, `sources.conf` and the `liseuse` launcher into `~/.local/bin`, creates `~/Livres` and registers the document MIME types. `Super + F`, and `F1` inside a book for the reading manual.

Also installs `python3-markdown`, `python3-pymdown-extensions`, `python3-pygments` and `python3-weasyprint` for the Markdown half. mupdf has no markdown parser, so `md2pdf.py` renders a `.md` to a PDF first and everything downstream — dark theme, reading position, ranking — works on an ordinary document. GFM coverage comes from the pymdown extensions (tables, strikethrough, task lists, autolinks, footnotes) and the syntax highlighting is Pygments' `github-dark`, which is GitHub's own palette. Not a headless browser: nothing in these documents needs JavaScript.

Every row in the picker carries a format icon, because a title alone never says which you are about to open — a course's `.md` notes and its `.pdf` slides both read as `RESEAUX · Routage`. All five glyphs come from one Nerd Font set (Material Design) so they share a weight and an advance width, which also means every title starts at the same x; fuzzel draws them through the same fontconfig fallback `fuzzel.ini` already relies on. Searching is fuzzel's own fzf matching, but against a hidden column holding the full path below `$HOME` twice, once as written and once flattened to words: typing `dotfiles keybind`, `courses reseaux` or just `md` finds documents whose visible title contains none of those.

`liseuse convert [FILE…]` renders `.doc`, `.docx`, `.odt`, `.rtf`, `.ppt`, `.pptx`, `.odp`, `.xls`, `.xlsx` and `.ods` to a PDF **beside the original**, which is the whole trick: the next scan finds that PDF like any other book, with no special case anywhere else. With no argument it offers a picker of what it found, marking the ones already converted. A source newer than its PDF is redone; one that is not is left alone, so a hand-made PDF sitting next to a `.doc` is never clobbered.

Unlike Markdown, office documents are **not** rendered transparently on open, and LibreOffice is deliberately **not** in this module's package list: headless conversion takes seconds per document and the suite is several hundred megabytes, which is the wrong trade to put behind every `Super + F`. The command says what to install if it is missing (`libreoffice-writer libreoffice-impress libreoffice-calc`).

`Space` and `Return` turn the page (with `Shift` for the previous one), and what that means depends on the document's shape, read from its first page with `mutool`: a **landscape** one — slides — turns a page and re-fits it whole, so zooming in on a detail does not leave the next slide cropped; a **portrait** one scrolls as a continuous strip and a page turn centres the new page without touching your zoom, because a page read at full width is meant to be scrolled through, not replaced. The per-document half is appended to the generated zathura config alongside the theme.

**A book opens as an ordinary tiled window**, and nothing in this module ever changes that: there is no `fullscreen` window rule and no code that sets the mode. Fullscreen is right for a deck of slides in a dark room and wrong for most of what actually gets read — a reference PDF beside an editor, a handout being copied from, two documents compared — so forcing it on open meant starting almost every session by pressing `Super + Shift + F` to undo it. It remains one keystroke away for the case where it *is* what you want. Tiled is also the state in which the bar earns its place: it names the window **Liseuse** and shows `[page/total] document`, read from zathura's own live window title, which updates on every page turn — no polling, no second source of truth. Opening a second book needs no special handling either: this Hyprland drops a fullscreen window out of the mode by itself when another window opens on its workspace, so the two simply tile.

**The workspace is the unit.** Every question of the form "is a book already open?" is scoped to the workspace `Super + F` was pressed on, and that is the fix for a bug this module shipped with: a book open anywhere used to answer for the keypress, so wanting a *new* document meant being thrown to the other workspace and pressing `Super + F` a second time to finally reach the picker. A book elsewhere is now neither focused nor counted — it keeps its own fullscreen and its own layout, to be found as you left it. Not being disturbed is the one thing that stays global: notifications and the idle inhibitor are quieted by the first session in and restored by the last one out, wherever the windows are, because a notification has no geometry. The layout side is counted in *windows* rather than in sessions, so a zathura opened from nemo or a terminal — which has no `liseuse` session behind it — still counts as sharing the workspace.

Note for anyone editing the scripts here: this Hyprland is configured in Lua, so `hyprctl dispatch` evaluates its argument **as Lua**. `hyprctl dispatch focuswindow address:0x…` does not misbehave, it fails to parse — which is how the "return to your book" half of `Super + F` sat broken and silent. Dispatches go through `hl.dsp.*` (`hl.dsp.focus`, `hl.dsp.window.fullscreen`, `hl.dsp.send_shortcut`).

Both halves follow the desktop's light/dark switch — the same `org.gnome.desktop.interface color-scheme` key quickshell's `AppearanceState.qml` reads and writes, so the bar's toggle drives the reader too. In light mode zathura's `recolor` is turned off (a PDF's own black-on-white is already what you want there) and Markdown renders on a light palette. Dark mode is the one place the reader leaves `colors.lua` behind: the page is pure black, not the palette's `#1c1c1e`. That palette is tuned for a bar and a launcher — small surfaces glimpsed over a wallpaper, where a near-black is what makes them read as surfaces — whereas a book is the whole screen for an hour, and a ground that is not quite black is a grey glow behind every line. Both halves use the same black, so switching between a `.md` and a `.pdf` is not a visible flash, and the elevation scale runs upward from it (`#141416` listings and alternate table rows, `#242426` hairlines, `#2c2c2e` inline code and table headers). The side effect is intended: with the window's own background the same black, the page edge disappears and a fullscreen slide simply floats. Since zathura's config language has no conditional and no usable include, `liseuse` assembles a themed copy of `zathurarc` into `~/.cache/liseuse/zathura/` on each open and launches with `--config-dir`; the history database is untouched by that.

Page geometry is never hardcoded. `md2pdf.py` asks the compositor for the focused monitor and derives the page from its real aspect (rotation included), and `Space` is bound to `feedkeys "Ja"` — next page, then best-fit — so zathura recomputes the zoom from the live viewport on every turn. A 16:9 deck on a 16:10 laptop, a 4:3 scan on an ultrawide and a rotated portrait panel all work with nothing to adjust, and a zoomed-in slide does not leave the next one cropped.

Rendered PDFs are cached in `~/.cache/liseuse/md/`, keyed on the mtimes of both the source and `markdown.css` plus the theme and screen aspect (kept in a `.meta` sidecar rather than in the filename, so switching theme does not lose your reading position). A `.src` sidecar next to each one names the source, which is how a reading position zathura recorded against a cache filename finds its way back to the `.md` in the picker. Links between markdown documents work: `md2pdf.py` rewrites them to absolute `file://` URIs and a `liseuse-markdown.desktop` handler brings them back here.

---

## Opt-in

### `boot/login`

**greetd + tuigreet** on VT1, replacing the display manager. Interactive: it asks before touching system login.

```bash
./install greeter        # `./install login-manager` still works
```

**The console draws in JetBrains Mono.** A Linux VT does not render through fontconfig — it draws from a PSF bitmap font handed to the kernel by `setfont` — so [`make-console-font.py`](../config/boot/login/make-console-font.py) rasterises the outlines into one and `console/` carries the result. It writes PSF2 directly rather than piping through `otf2bdf | bdf2psf`, because those are two conversions and two chances to lose the one decision that decides whether a 1-bit rasterisation is legible: where the threshold sits. `--preview` renders the font back out of its own bytes, which is also the only check that the packing and glyph order are right.

The box-drawing glyphs are **drawn, not rasterised**, and the measurement says why. At 24px JetBrains Mono has a 14.4px advance and a 33px line height, but `U+2502` draws 37 rows of ink and `U+2500` draws 16 columns: the box glyphs deliberately overhang so they tile, on a cell whose aspect ratio is about 2.57. A cell wide enough to match would need more rows than the kernel's 32 — so there is no legal cell where those glyphs join, and rasterising them gives a border in disconnected fragments. Generating them puts the arms on the cell edges by construction. The dashed and double-line variants are deliberately absent rather than approximated: nothing here draws with them, and a missing glyph shows as the kernel's fallback, where one built wrong shows as a border that almost lines up.

**The glyph order is a contract, and breaking it produced the strangest screen of the whole module**: a greeter whose background was a solid field of `@`. The console's screen buffer stores *glyph indices*, not characters, so text painted before a font swap keeps its indices and is re-rendered with the new font. tuigreet had drawn its background of spaces under the kernel's built-in font, where space is glyph 32 — and this font's glyph 32 was `@`, because ASCII started at index 0 (`chars[32] = 0x20 + 32 = 0x40`). Fedora's own fonts avoid this by convention: `latarcyrheb-sun32` maps glyph 32 to U+0020, 65 to U+0041, 97 to U+0061 — identity for Latin-1, extras above 255. The generator now does the same, which pushes the count to 512 (the other legal size); 512-glyph mode spends the intensity bit on glyph selection, leaving eight background colours, and the greeter draws named ANSI colours on black so it never notices. The repair script also clears VT1 after loading the font — harmless now, but it removes the class of problem rather than the instance.

**The count is exactly 256 or 512, and that is a hard requirement, not a round number.** `fbcon` accepts a console font of 256 or 512 glyphs and refuses anything else, with a message that names neither the count nor the rule: `setfont: ERROR kdfontop.c:240 put_font_kdfontop: ioctl(KDFONTOP): Invalid argument`. This font first came to 238 and was rejected for that alone — its geometry was already the shape Fedora's own 16x32 font uses. What found it was measuring every console font on the system: 512, 512, 256, and ours at 238. The generator pads to the next legal count with blank glyphs carrying an empty Unicode entry, so nothing can land on them.

The cell is **8x16**, the size a Linux console has always been, which on this 1920x1200 panel gives 240x75 characters. `--cell WxH` changes it and the output filename follows, so `vconsole.conf`'s `FONT=` follows too — and `install.sh` reads the name back out of that file rather than keeping its own copy, since a second copy could drift and the console would quietly fall back to the kernel default. The rasterisation size and baseline are derived from the cell rather than fixed, so a different cell needs no second adjustment.

**It also repairs the keyboard**, which it did not break. `systemd-vconsole-setup` applies the font and the keymap together and abandons *both* when `setfont` fails — logging `Configuration of first virtual console failed, ignoring remaining ones`. It fails on every early attempt here because Plymouth holds VT1 in `KD_GRAPHICS` mode and a font cannot be written to a console in that state. The keymap only ever landed because one late retry happened to win a race against greetd starting. `console-setup-late.service` removes the race: it runs after `plymouth-quit-wait`, applies the keymap **first**, and cannot fail the boot.

Its ordering is `After=plymouth-quit-wait.service` and `Before=greetd.service`, and nothing else — which is the second half of the lesson. An earlier version also said `Before=systemd-user-sessions.service`, which looks harmless and is not: `plymouth-quit-wait` is itself ordered *after* `systemd-user-sessions`, so that one extra word closed a cycle, and systemd broke it the only way it can — `Job console-setup-late.service/start deleted to break ordering cycle`. The unit was enabled, reported itself enabled, and never ran once. `greetd` is already ordered after `plymouth-quit-wait`, so `Before=greetd.service` alone places it exactly where it needs to be. A font that will not load now costs a typeface instead of a layout.

**Two greeters were tried here and both reverted**, which is recorded so neither gets tried a third time by someone reading only the result.

**regreet** (GTK4, under `cage`) was too rigid, and it cost a near-lockout: cage takes its keyboard layout from XKB rather than from `/etc/vconsole.conf`, so with nothing setting `XKB_DEFAULT_LAYOUT` the greeter came up in US QWERTY on an AZERTY machine, at a masked password prompt.

**ly** had what looked like the better argument — Fedora packages it, where tuigreet supposedly came from a copr. That turned out to be stale: Fedora ships `tuigreet` too, and this module had simply been asking for `greetd-tuigreet`, a name no enabled repository provides. `verify` had been reporting it missing for as long as anyone could remember, next to two ghosts left by a renamed module, which is how a check stops being read. It cost three separate lockouts before it ran at all, and each one is a lesson that outlived it:

- A `•` in `asterisk` made ly **discard its entire config file** and run on defaults. It does not skip an option it cannot parse, and says so nowhere except `/var/log/ly.log`. Three bytes of UTF-8 where the option takes one character.
- `session_log` then defaulted back into `$HOME`, which `xdm_t` may not create files in, and ly treats failing to open that log as fatal to the session. A login authenticated correctly and vanished in the same second, reported at the prompt as `AccessDenied`.
- A hand-written minimal config dropped the `/bin/sh` Fedora puts in front of its non-executable `setup.sh`. Keys omitted from a config do not fall back to the *distribution's* defaults — they fall back to the program's **compiled-in** defaults, and those differ.

It also raised a real question worth keeping: `ly-kmsconvt@.service` runs ly inside **kmscon**, which replaces the VT and renders through pango — a real vector font at any size, no 512-glyph ceiling, no synthesised box drawing. The catch is that kmscon takes its keyboard from XKB, exactly the trap regreet fell into, though there it is a deliberate option (`--xkb-layout fr --xkb-variant oss`) rather than an invisible default. That remains the one route to a properly-rendered font at the login screen, and it is a step onto the login path, so it is not taken by accident.

tuigreet asks the console keymap for its layout, like everything else on a VT, and greetd passes the session command straight through. What the experiments left behind is kept: the console renders in JetBrains Mono, the keymap repair survives Plymouth holding the VT, and the word stays on screen through the gap before the first frame.

**The black gap when Hyprland starts** is closed by [`session-splash.sh`](../config/boot/login/session-splash.sh), which greetd's `--cmd` points at. A VT keeps showing whatever was last drawn on it until something takes the display away, and what takes it away is Hyprland's first modeset — so writing the word to the console immediately before `exec`ing the session leaves it up for exactly the length of the gap, and it disappears because the desktop replaced it rather than because anything timed out. It is text in the console font, placed at `LOGO_CENTRE`, where `coucou.script` puts the word mark, so the continuity is real even though the mechanism is trivial. No second Plymouth: re-showing the animated splash would mean a daemon holding DRM master while the compositor is trying to take it, which is a fight over the device to save a second.

### `kde`

A minimal Plasma session as an alternate login. Installs ~15 packages with `--allowerasing`, which is why it keeps its own install call rather than going through `pkg_ensure`: it deliberately replaces conflicting packages, and that is not a decision the shared helper should ever make on its own.

Currently broken upstream — see the table at the top of this page.
