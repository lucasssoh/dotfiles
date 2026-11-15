# `cc-pkg-mng`

This is coucou-shell's own package manager. It installs the parts of coucou-shell, keeps them up to date, and lets you move between releases. For the very first install, start with [installation.md](installation.md).

## Everyday use

```bash
cc-pkg-mng upgrade    # move to the latest release (or the latest commit, on edge) and apply it
cc-pkg-mng status     # what's installed, and whether it's in place
```

An install or an upgrade shows as a live list: the step in progress unfolds, finished steps fold to one line. A step that fails stays open, with its last lines and the path of the full log.

![An upgrade in progress](screenshots/v1.3.0/cc-pkg-mng-upgrade.webp)

![The same upgrade, done](screenshots/v1.3.0/cc-pkg-mng-done.webp)

In a pipe, with `--verbose` or with `-q`, the output is one line per step. The full log is in `~/.local/state/coucou-shell/logs/`.

`cc-pkg-mng` alone, or `--help`, lists the commands by what they are for:

![cc-pkg-mng's help](screenshots/v1.3.0/cc-pkg-mng-help.webp)

## Units and layers

coucou-shell is split into **units**, grouped in three layers:

| Layer | What's in it | When it's installed |
|---|---|---|
| **core** | The shell itself: Hyprland, the bar, Roue, Prisme, Balise, Manette, Sésame, Liseuse, fonts, theme, drivers | Always. The login screen, the boot splash and Programme are optional |
| **apps** | Default applications: WezTerm, Firefox, Nemo, Neovim, mpv, and a few extras | Only the ones you pick. You can swap any of them for another app |
| **configs** | My personal setups for the shell, WezTerm, Neovim and a few apps | Only if you choose to adopt them |

`cc-pkg-mng list` shows every unit, and `cc-pkg-mng info <unit>` shows what one contains. The [units](units.md) page lists them all, with their guides.

## Commands

| Command | What it does |
|---|---|
| `init` | Sets up the machine: the checkout, the channel and the units. See [installation.md](installation.md) |
| `list` | Lists every unit by layer, with `●` next to the installed ones. Takes `--installed` and `--layer core\|apps\|configs` |
| `info <unit>` | Shows what a unit installs, links and runs, and which units it needs |
| `install <unit>…` | Installs units, along with any units they need |
| `remove <unit>…` | Removes units: unlinks their files, restores what they replaced, and turns their services off. Their packages stay installed |
| `status` | Shows the checkout, the channel, and the state of each installed unit: up to date, changed since it was installed, or with broken links |
| `upgrade` | Moves to the latest release (stable) or the latest commit (edge), then applies whatever changed. `--to vX.Y.Z` picks a specific release |
| `rollback` | Goes back to the release you had before the last upgrade (stable only) |
| `channel [stable\|edge]` | Shows the current channel, or switches to another one. The next `upgrade` follows it |
| `dev [<unit>…]` | Runs one of coucou-shell's [own apps](#channels) built from the checkout you're in (stable only). With no unit, shows what is running. `--off` goes back to the release's, `--from <path>` builds from another checkout. See [testing your changes](#testing-your-changes-on-stable) |
| `set <unit> <question> <value>` | Changes one of your answers, for example `set wezterm variant smear`. Run `install wezterm` afterwards to apply it |

## Options

| Flag | Effect |
|---|---|
| `-n`, `--dry-run` | Show the plan without changing anything |
| `-y`, `--yes` | Accept every default: no questions, no confirmation |
| `--dir <path>` | Use this coucou-shell checkout. It's remembered for next time |
| `-q`, `--quiet` | Only print warnings and errors |
| `--verbose` | Show the output of every command as it runs |
| `--no-color` | Plain output, no colours |
| `--version` | The manager's version, the release this machine runs, its channel, whether a newer release is out, and the apps running from your checkout |
| `-V` | The manager's version alone, on one line |

## Channels

| Channel | Follows | coucou-shell's own apps |
|---|---|---|
| **stable** | releases (`v1.0.0` and so on) | Installed from coucou-shell's repository, at the version that matches the release |
| **edge** | every commit on the default branch | Built on your machine into `~/.local/bin`, and rebuilt whenever their code changes. The Rust toolchain is installed for this |

The own apps are Roue, Prisme, Balise, Manette, Sésame, Pouls and Programme.

## Testing your changes on stable

To work on one of coucou-shell's own apps while staying on stable, code in a second checkout (`~/code/dotfiles`, on `master`). From that checkout:

```bash
cc-pkg-mng dev roue       # build Roue from here, and run it instead of the release's
cc-pkg-mng dev            # what is running instead of the release
cc-pkg-mng dev --off      # back to the release's apps
```

- Your shortcuts and the bar use the new build at once.
- Run `dev` again after each change. The first build takes a minute or two, the next ones a few seconds.
- An `install` or `upgrade` that touches the unit puts the release's version back. Its plan says so.
- `status` lists the dev builds that are running.
- The first `dev` installs the Rust toolchain.

On edge, `cc-pkg-mng install roue` rebuilds what changed.

You can see what each release changed in the [changelog](../CHANGELOG.md).

## What to expect

- A command that changes the machine shows its plan and waits for your OK. Your password is asked once.
- A unit whose files haven't changed is skipped.
- A file of yours that a unit replaces goes to the backups. `remove` puts it back.
- `upgrade` and `rollback` stop when a file of the checkout has changed, and list the files. See [keep a change through an upgrade](configuration.md#keep-a-change-through-an-upgrade).
- A program that is running keeps its old version until you restart it. The bar reloads itself, and the sound cuts out for a moment when the audio configuration changes.
- `sudo dnf upgrade` updates coucou-shell's own apps too. Run `cc-pkg-mng upgrade` afterwards to bring the rest to the same release.

## Files

Everything the manager keeps track of is in `~/.local/state/coucou-shell/`:

| Path | Contents |
|---|---|
| `state.toml` | The checkout, the channel, the version, and each installed unit with your answers |
| `dev/` | The dev builds running in place of the release's, and where each came from |
| `backups/` | Files that units replaced, sorted by date |
| `logs/` | The full output of every run |

## Exit codes

`0` when everything went fine. `1` for any error, such as a step that failed, a plan you cancelled, a unit that doesn't exist, or uncommitted changes in the way.
