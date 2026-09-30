# `cc-pkg-mng`

The coucou-shell package manager: it installs coucou-shell's parts, keeps them up to date, and moves between releases. For the first install, see [installation.md](installation.md).

## Everyday use

```bash
cc-pkg-mng upgrade    # move to the latest release (or commit, on edge) and apply it
cc-pkg-mng status     # what is installed, and whether it is in place
```

## Units and layers

coucou-shell is made of **units**, in three layers:

| Layer | What | Installed |
|---|---|---|
| **core** | The shell itself: Hyprland, the bar, Roue, Prisme, Balise, Liseuse, fonts, theme, drivers | always; the login screen and the boot splash are optional |
| **apps** | Default applications: WezTerm, Firefox, Nemo, Neovim, mpv, and a few extras | the ones you pick; each is replaceable by any other app |
| **configs** | Personal setups for the shell, WezTerm, Neovim and a few apps | only when you adopt them |

`cc-pkg-mng list` shows every unit, `cc-pkg-mng info <unit>` what one contains. The units themselves are described in [modules.md](modules.md).

## Commands

| Command | |
|---|---|
| `init` | Sets up the machine: the checkout, the channel, the units — see [installation.md](installation.md) |
| `list` | Every unit, by layer, `●` when installed. `--installed`, `--layer core\|apps\|configs` |
| `info <unit>` | What a unit installs, links and runs, and what it requires |
| `install <unit>…` | Installs units, and the units they require |
| `remove <unit>…` | Takes units away: unlinks their files, puts back what they replaced, turns their services off. Their packages stay installed |
| `status` | The checkout, the channel, and each installed unit: up to date, changed since installed, or with broken links |
| `upgrade` | Moves to the latest release (stable) or the latest commit (edge), then applies what changed. `--to vX.Y.Z` picks a release |
| `rollback` | Back to the release before the last upgrade (stable only) |
| `channel [stable\|edge]` | Shows or switches the channel; the next `upgrade` follows it |
| `set <unit> <question> <value>` | Changes an answer, e.g. `set wezterm variant smear`; `install wezterm` then applies it |

## Options

| Flag | |
|---|---|
| `-n`, `--dry-run` | Show the plan; change nothing |
| `-y`, `--yes` | Take every default: no questions, no confirmation |
| `--dir <path>` | The coucou-shell checkout to use; remembered for next time |
| `-q`, `--quiet` | Warnings and errors only |
| `--verbose` | Show every command's output as it runs |
| `--no-color` | Plain output |
| `-V`, `--version` | The manager's version |

## Channels

| Channel | Follows | Roue, Prisme, Balise |
|---|---|---|
| **stable** | releases (`v1.0.0`, …) | installed from coucou-shell's repository, at the release's version |
| **edge** | every commit on the default branch | built on the machine into `~/.local/bin`, again whenever their sources change (the Rust toolchain is installed for it) |

Switching from edge to stable removes the local builds, so the packaged ones take over.

A release's changes are listed in the [changelog](../CHANGELOG.md).

## How it behaves

- **One plan, one confirmation.** Every command that changes the machine first shows what it will do. The password is asked once, and every package goes in one dnf transaction.
- **Only what changed.** A unit whose files did not change since it was applied is left alone; running the same command twice does nothing the second time.
- **Your files are kept.** A file that a unit would replace is moved to the backups first, and `remove` puts it back.
- **Local edits block a version change.** `upgrade` and `rollback` stop if the checkout has uncommitted changes, and say which files.
- **Nothing is restarted** except the audio stack when its configuration changes. Running programs keep their old version until they restart; the bar reloads itself.
- **dnf and the Rust apps.** A plain `sudo dnf upgrade` also upgrades Roue, Prisme and Balise to the newest release; the next `cc-pkg-mng upgrade` brings the rest up to the same release.

## Files

Everything the manager keeps is in `~/.local/state/coucou-shell/`:

| Path | |
|---|---|
| `state.toml` | The checkout, the channel, the version, and each installed unit with its answers |
| `backups/` | Files that units replaced, by date |
| `logs/` | The full output of every run |

## Exit codes

`0` on success, `1` on any error: a failed step, a cancelled plan, an unknown unit, uncommitted changes.
