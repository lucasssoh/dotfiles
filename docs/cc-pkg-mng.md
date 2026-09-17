# `cc-pkg-mng`

The install and update manager for this repo. Source: [`bin/cc-pkg-mng`](../bin/cc-pkg-mng), with its libraries under [`scripts/lib/`](../scripts/lib).

For the first install on a new machine, see [installation.md](installation.md). For state, environment variables and the module registry, see [configuration.md](configuration.md).

## Everyday use

```bash
cc-pkg-mng update     # pull, then apply the modules whose contents changed
cc-pkg-mng verify     # check links, binaries, packages and units
```

## Commands

| Command | Description |
|---|---|
| `status` | Per-module state: up to date, changed, never applied, or last run failed. Also crate staleness and any repo path no module claims. Read-only; contacts the network only with `--fetch`. Always exits 0 |
| `update` | Pulls fast-forward only, then runs the `install.sh` of every module whose fingerprint moved, in registry order |
| `install` | Fresh-machine path: ignores state and runs every module. System scope unless `--user`. This is what `./install` delegates to |
| `verify` | Six checks: registry, symlinks, binaries, declared packages, systemd units, and with `--full` the runtime dependencies |
| `build [crate]` | Builds the Rust crates, skipping any whose sources and toolchain are unchanged. No argument means all three |
| `needs-restart` | Lists processes running a binary that has since been replaced |
| `clean --cargo` | Removes the cargo target directory and the legacy `~/.cache/*-build` trees |
| `help` | Usage |

## Options

| Flag | Applies to | Effect |
|---|---|---|
| `-n`, `--dry-run` | all | Print what would happen; change nothing |
| `--only <module>` | `update`, `install` | Restrict to one module. Repeatable |
| `--force` | `update`, `build` | Act even when nothing changed |
| `--no-pull` | `update` | Skip the pull and apply the working tree as it is |
| `--system` | `update` | Allow root-owned steps |
| `--user` | `install` | User scope only |
| `--adopt` | `update` | Record the current fingerprints as applied, without running anything |
| `--strict` | `update`, `verify` | Treat deferrals and warnings as failures |
| `--fetch` | `status` | Contact origin to report how many commits behind |
| `--porcelain` | `status` | `key<TAB>value` output |
| `--full` | `verify` | Also run the runtime-dependency scan |
| `--fix` | `verify` | Re-run the modules owning a hard problem |
| `-q`, `--quiet` | all | Warnings and errors only |
| `--no-color` | all | Plain output |
| `-V`, `--version` | | Print the repo revision this script came from |

## Behaviour

### Privilege scope

`update` runs in user scope. A package that is already installed is detected with `rpm -q`, which needs no root and answers in milliseconds, so nothing is asked of you. A package that is genuinely missing is **deferred**: listed at the end of the run and left for an explicit `cc-pkg-mng update --system`.

```
Deferred (needs --system):
  firefox	cmd: mkdir -p /etc/firefox/policies
  hyprland	cmd: dnf copr enable -y mineiro/satty
  → cc-pkg-mng update --system
```

Deferrals do not fail the run — the files, links and binaries are all in place. `--strict` changes that, for callers that need "fully applied or nothing".

`install` is the reverse: system scope unless `--user`.

### Nothing is restarted

Files and binaries are put in place; running processes keep the version they started with, and the new one takes effect the next time each starts. What is affected is reported at the end of an `update`, or on demand:

```
$ cc-pkg-mng needs-restart
These are still running an older version:
  balise               binary replaced since it started
                       -> systemctl --user restart balise.service
```

The report is read off `/proc`, not inferred: a process whose `/proc/<pid>/exe` ends in ` (deleted)` is holding a binary that has been replaced, and a binary whose mtime is newer than the process start time was modified under it. `quickshell` is deliberately excluded — it watches its own QML and reloads itself.

### A dirty worktree stops the pull

`update` refuses to pull over uncommitted changes and lists them:

```
Uncommitted local changes:
   M config/nvim/init.lua
[ ERR]  refusing to pull over them. Commit, stash, or re-run with --no-pull to apply local work only.
```

`--no-pull` applies the working tree as it is, which is how you test an edit before committing it.

### A failed module is retried

A module whose last run exited non-zero is re-run on the next `update` even when its contents have not changed — a failure is often environmental (a repo outage, no network), and the fingerprint has not moved to signal it.

### Interruption is safe

State is written per module, immediately after each one finishes. A run stopped with Ctrl-C keeps everything it actually completed; the next `update` resumes with the rest.

## Exit codes

| Code | Meaning |
|---|---|
| 0 | Success. Deferred root-owned steps do not fail a run unless `--strict` is given |
| 1 | `update`: a module failed, or `--strict` with deferrals. `verify`: a hard problem, or `--strict` with warnings. Also an inconsistent registry, a dirty worktree blocking the pull, or a diverged branch |
| 2 | `verify` only: the check could not run at all (not a git repository) |

`status` always exits 0.

## What `verify` checks

| Check | Failure level | Source of truth |
|---|---|---|
| Registry | hard | `config/` on disk versus [`scripts/lib/modules.sh`](../scripts/lib/modules.sh) |
| Symlinks | hard | `links.ledger` — every destination is a link, resolves to its source, and the source still exists |
| Binaries | hard (missing or shadowed), warning (stale) | `~/.local/bin`, plus `command -v` resolving there and not somewhere earlier in `PATH` |
| Declared packages | hard | `packages.ledger`, each name through `rpm -q` |
| systemd units | warning | `config/hyprland/systemd/*.service` linked, not failed |
| Runtime dependencies | warning, `--full` only | [`scripts/check-deps.sh`](../scripts/check-deps.sh) |

The two ledgers are written by `safe_link` and `pkg_ensure` as they run, so they record what actually happened rather than a separate list of what should exist. The honest scope of `verify` is therefore modules that have run at least once on this machine.

`--fix` re-runs the modules owning any hard problem, then tells you to verify again.

## Logs

Every run writes a full log under `~/.local/state/dotfiles/`, with `latest.log` pointing at the most recent one:

```bash
less ~/.local/state/dotfiles/latest.log
```

The terminal shows one line per module; the log holds the complete output of each, framed with start/end markers and the exit code and duration.
