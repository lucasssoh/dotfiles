# `cc-pkg-mng`

The install and update manager for this repo: [`bin/cc-pkg-mng`](../bin/cc-pkg-mng).

For the first install, see [installation.md](installation.md). For state, environment variables and the module registry, see [configuration.md](configuration.md).

## Everyday use

```bash
cc-pkg-mng update     # pull, then apply the modules whose contents changed
cc-pkg-mng verify     # check links, binaries, packages and units
```

## Commands

| Command | Description |
|---|---|
| `status` | Per-module state: up to date, changed, never applied, or last run failed. Also crate staleness and repo paths no module claims. Read-only |
| `update` | Pulls (fast-forward only), then runs every module whose contents changed, in registry order |
| `install` | Fresh-machine path: runs every module regardless of state. System scope unless `--user`. This is what `./install` calls |
| `verify` | Checks the registry, symlinks, binaries, packages, systemd units, and with `--full` the runtime dependencies |
| `prune` | Removes the links left behind by files deleted from the repo (disabling a user unit first). `-n` to preview |
| `build [crate…]` | Builds the Rust crates that changed. No argument: all of them |
| `wezterm [stable\|smear]` | Prints or switches the wezterm variant — see [modules.md](modules.md#wezterm) |
| `needs-restart` | Lists processes still running a binary that has since been replaced |
| `clean --cargo` | Removes the cargo target directory and old build caches |
| `help` | Usage |

## Options

| Flag | Applies to | Effect |
|---|---|---|
| `-n`, `--dry-run` | all | Print what would happen; change nothing |
| `--only <module>` | `update`, `install` | Restrict to one module. Repeatable |
| `--force` | `update`, `build` | Act even when nothing changed |
| `--no-pull` | `update` | Apply the working tree as it is, without pulling |
| `--system` | `update` | Allow root-owned steps |
| `--user` | `install` | User scope only |
| `--wezterm <variant>` | `install` | `stable` or `smear` |
| `--adopt` | `update` | Mark the current state as applied, without running anything |
| `--strict` | `update`, `verify` | Treat deferrals and warnings as failures |
| `--fetch` | `status` | Report how many commits behind origin |
| `--porcelain` | `status` | `key<TAB>value` output |
| `--full` | `verify` | Also check runtime dependencies |
| `--fix` | `verify` | Re-run the modules owning a hard problem |
| `-q`, `--quiet` | all | Warnings and errors only |
| `--no-color` | all | Plain output |
| `-V`, `--version` | | Print the repo revision |

## Behaviour

### Privilege scope

`update` never asks for a password. A root-owned step it cannot do — a missing package, a system file — is **deferred** and listed at the end:

```
Deferred (needs --system):
  firefox	cmd: mkdir -p /etc/firefox/policies
  hyprland	cmd: dnf copr enable -y mineiro/satty
  → cc-pkg-mng update --system
```

Deferrals do not fail the run unless `--strict` is given. `install` is the reverse: system scope unless `--user`.

### Nothing is restarted

Running programs keep their old version until they restart (the exceptions are the `pipewire` and `wireplumber` modules, which restart the audio stack). What is affected is reported at the end of an `update`, or with:

```
$ cc-pkg-mng needs-restart
These are still running an older version:
  balise               binary replaced since it started
                       -> systemctl --user restart balise.service
```

Quickshell is not listed: it reloads itself.

### Uncommitted changes stop the pull

```
Uncommitted local changes:
   M config/nvim/init.lua
[ ERR]  refusing to pull over them. Commit, stash, or re-run with --no-pull to apply local work only.
```

`--no-pull` is also how to test an edit before committing it.

### Failures and interruptions

A module that failed is retried on the next `update`, even if unchanged. A run stopped with Ctrl-C keeps the modules it finished; the next `update` does the rest.

## Exit codes

| Code | Meaning |
|---|---|
| 0 | Success (deferrals included, unless `--strict`) |
| 1 | `update`: a module failed, or `--strict` with deferrals. `verify`: a hard problem, or `--strict` with warnings. Also: inconsistent registry, dirty worktree, diverged branch |
| 2 | `verify`: could not run at all (not a git repository) |

`status` always exits 0.

## What `verify` checks

| Check | Level |
|---|---|
| Registry matches `config/` | hard |
| Every recorded symlink is in place | hard |
| Binaries in `~/.local/bin`, first on `PATH` | hard (missing or shadowed), warning (stale) |
| Every package a module declared is installed | hard |
| `systemd --user` units linked and not failed | warning |
| Runtime dependencies ([`scripts/check-deps.sh`](../scripts/check-deps.sh)) | warning, `--full` only |

Only modules that have run at least once on the machine are checked. `--fix` re-runs the modules owning a hard problem.

## Logs

Each run writes a full log under `~/.local/state/dotfiles/`:

```bash
less ~/.local/state/dotfiles/latest.log
```
