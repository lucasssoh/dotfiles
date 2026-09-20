# Configuration

How the manager stores state, what you can change, and how to add to it. For the commands themselves see [cc-pkg-mng.md](cc-pkg-mng.md).

## State and logs

Everything the manager remembers lives in `${XDG_STATE_HOME:-~/.local/state}/dotfiles/`:

| File | Contents |
|---|---|
| `state.v1` | `key<TAB>value`: per-module fingerprint, exit code, duration and timestamp; per-crate build key |
| `links.ledger` | `module<TAB>source<TAB>destination`, written by `safe_link` as it runs. Read by `verify` |
| `packages.ledger` | `module<TAB>package`, written by `pkg_ensure`. **Rewritten per module on each run**, not appended: it answers *what does this module depend on now*, so a package dropped from a module stops being demanded. Read by `verify`, which also skips any module no longer in the registry |
| `deferred.ledger` | Root-owned steps skipped during the last run. Truncated at the start of each one |
| `install-*.log`, `latest.log` | Full output of each run, one file per run |

`state.v1` is plain text, sorted, and never sourced — it is data, not code.

It also has more than one writer: a module runs as its own process and records its crate build keys from there, while the manager that launched it is holding an older copy. So a save **merges** — it re-reads the file and rewrites only the keys that process itself touched, removals included. Whoever saves last no longer wins the whole file, which is what used to silently drop the `crate.*` keys a module had just written.

```
schema	1
mod.nvim.applied	2026-09-17T09:39:49+02:00
mod.nvim.fp	a6a0406707b41f8c…
mod.nvim.rc	0
crate.roue.key	54c00228…|cargo 1.98.1 (797e8a9bc 2026-08-05)
```

| To | Do |
|---|---|
| Force a full re-apply | `rm ~/.local/state/dotfiles/state.v1`, or `cc-pkg-mng update --force` |
| Mark an already-configured machine as current | `cc-pkg-mng update --adopt` — records fingerprints without running anything |
| Re-apply one module | `cc-pkg-mng update --force --only <name>` |

The `schema` key is the reset lever: bumping `STATE_SCHEMA` in [`scripts/lib/state.sh`](../scripts/lib/state.sh) makes every machine do one full re-apply, which is the correct behaviour when the meaning of the stored values changes.

## Environment variables

| Variable | Default | Effect |
|---|---|---|
| `STATE_DIR` | `~/.local/state/dotfiles` | Where state, ledgers and logs are written |
| `CARGO_TARGET_ROOT` | `~/.cache/dotfiles/cargo-target` | Shared cargo target directory for the three crates |
| `CCPKG_ALLOW_ROOT` | `1` | `0` defers every root-owned step instead of running it. `update` sets this itself |
| `CCPKG_MODULE` | the module's path under `config/` | Which module the ledgers attribute an entry to. The path, not the basename, so a nested module (`boot/login`) records the same name whether it was run by `cc-pkg-mng` or by hand |

## The module registry

[`scripts/lib/modules.sh`](../scripts/lib/modules.sh) holds the list and its constraints:

| Name | Purpose |
|---|---|
| `MODULE_ORDER` | The modules, in the order they run. The order is the contract |
| `MODULE_OPTIN` | Modules that exist but are never run by default, each with its reason |
| `MODULE_AFTER` | Ordering constraints — `[liseuse]="fuzzel"`, or `"@last"` for the trailing block |
| `MODULE_LAST_BLOCK` | How many entries form that trailing block |

`registry_validate` runs on **every** invocation and checks four things:

1. every registered module has an `install.sh`;
2. every `config/*/install.sh` on disk is registered somewhere;
3. no duplicates in `MODULE_ORDER`;
4. every `MODULE_AFTER` constraint holds.

Any failure stops the command and names the module and the file to edit. Check 2 is the one that matters: a module added to the repo but to no list would otherwise be silently never run.

### Adding a module

1. Create `config/<name>/install.sh` and make it executable.
2. Add `<name>` to `MODULE_ORDER`, at the position its dependencies require — or to `MODULE_OPTIN` to keep it out of default runs.
3. Add an entry to `MODULE_AFTER` if it must follow another module.

Until step 2 is done, every `cc-pkg-mng` command fails and says which file to edit.

Inside the module, source the shared helpers rather than writing your own:

```bash
#!/usr/bin/env bash
set -Eeuo pipefail

. "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../../scripts/lib/pkg.sh"
. "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../../scripts/lib/link.sh"

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

pkg_ensure tmux wl-clipboard                       # only installs what is missing
pkg_ensure "$(pkg_pick fd-find fd fd-find)"        # dnf / pacman / apt name
sudo_maybe systemctl enable --now foo              # deferred in user scope
safe_link "$DOTFILES_DIR/config/<name>/x.conf" "$HOME/.config/x.conf"
```

| Helper | Source | Behaviour |
|---|---|---|
| `pkg_ensure` | [`pkg.sh`](../scripts/lib/pkg.sh) | Records every name in the ledger, installs only the absent ones, defers when not allowed to use root |
| `pkg_pick` | `pkg.sh` | Picks the right package name for the current distro |
| `pkg_installed` | `pkg.sh` | Query only, no root |
| `sudo_maybe` | `pkg.sh` | Runs under sudo, or defers and reports |
| `safe_link` | [`link.sh`](../scripts/lib/link.sh) | Returns early if the link is already correct; backs a real file up to `.bak` rather than overwriting |

## Rust crates

`RUST_CRATES` in [`scripts/lib/rust.sh`](../scripts/lib/rust.sh) maps each crate to its directory and the binaries it produces:

```bash
declare -A RUST_CRATES=(
    [balise]="config/hyprland/balise-src balise"
    [prisme]="config/hyprland/prisme-src prisme wallpaper-filter"
    [roue]="config/hyprland/roue-src roue"
)
```

A crate is rebuilt when its content fingerprint changes, when the `cargo --version` string changes, or when one of its binaries is missing from `~/.local/bin`. `--force` bypasses the check.

All three share one target directory (`CARGO_TARGET_ROOT`), outside the repo. Builds happen in place, so cargo's own incremental engine keeps its fingerprint database between runs.

```bash
cc-pkg-mng build            # all three, skipping what is current
cc-pkg-mng build roue       # one
cc-pkg-mng build --force    # ignore the staleness check
cc-pkg-mng clean --cargo    # drop the target directory
```

## How changes are detected

One content fingerprint per `config/<module>/`, stored in `state.v1` and compared on the next run.

- The file list comes from `git ls-files`, so **`.gitignore` decides what is excluded** — build output under `*-src/target/`, `__pycache__/` and the runtime JSON under `hypr/` never count.
- **Contents are hashed, not modification times.** `touch` alone triggers nothing; `cp`, `git checkout` and `git stash` all rewrite mtimes and would produce false positives.
- The file *list* is hashed alongside the contents, so a deletion or a rename moves the fingerprint even though no surviving file changed.
- Untracked files that are not ignored do count, so a new file you have not committed still triggers a re-apply.

### Paths outside `config/`

| Path | Target |
|---|---|
| `setup_fedora.sh` | the system phase |
| `scripts/lib/hardware.sh`, `scripts/install-hardware.sh`, `scripts/hardware-detect.sh` | the hardware phase |
| `wallpapers/` | the `hyprland` module |
| `bin/`, `scripts/`, `install`, `install_all.sh` | nothing — these change how the *next* run behaves, and are read fresh each time |
| anything else | listed by `status` under **Unmapped paths** |

The unmapped category is deliberate rather than a silent default: a new top-level directory cannot quietly fall outside the manager's world without showing up in `status`.
