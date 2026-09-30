# Configuration

What can be changed around the manager, and how to add a unit of your own. For the commands, see [cc-pkg-mng.md](cc-pkg-mng.md); for what each unit installs and where its settings live, see [modules.md](modules.md).

## Editing coucou-shell

Configuration files are **linked** from the checkout into place, never copied: edit the file in the checkout and the change is live once the program concerned reloads. `cc-pkg-mng status` then shows the unit as *changed since installed*; `cc-pkg-mng install <unit>` re-applies it when a change needs more than a reload (a new package, a hook).

On the stable channel, commit or stash your edits before `upgrade`: it refuses to move over uncommitted changes.

## Environment variables

| Variable | Default | Effect |
|---|---|---|
| `COUCOU_SHELL_URL` | `https://github.com/lucasssoh/dotfiles.git` | What `init` clones |
| `CCPKG_STATE_DIR` | `~/.local/state/coucou-shell` | Where the manager keeps its state, backups and logs |
| `CARGO_TARGET_ROOT` | `~/.cache/dotfiles/cargo-target` | Build directory for Roue, Prisme and Balise on edge |
| `HOST_PROFILE` | from the machine's DMI product name | Forces a machine profile — see [per-machine profiles](modules.md#per-machine-profiles) |

## Adding a unit

A unit is a directory `units/<layer>/<name>/` with a `unit.toml`. The next `cc-pkg-mng list` shows it, and `cc-pkg-mng install <name>` installs it.

```toml
name     = "tmux"
layer    = "apps"                 # core, apps or configs
summary  = "tmux, with the clipboard wired to Wayland"
requires = ["base"]               # installed first
default  = true                   # apps: ticked in init's list

[packages]
dnf   = ["tmux", "wl-clipboard"]
copr  = []                        # COPRs to enable first
repos = []                        # .repo URLs to add first

[links]                           # checkout path → destination
"config/tmux/.tmux.conf" = "~/.tmux.conf"

[services]
user   = []                       # systemd --user units to enable
system = []                       # system units to enable

[[questions]]                     # asked once, changed later with `set`
id      = "variant"
ask     = "Which build?"
choices = ["stable", "smear"]
default = "stable"

[[hooks]]                         # a script for what a declaration cannot say
name   = "plugins"
run_as = "user"                   # or "root"
does   = "clone the plugin manager into ~/.tmux/plugins"
run    = "units/apps/tmux/hooks/plugins.sh"
watch  = ["config/tmux"]          # re-run when any of these changes
```

| Key | |
|---|---|
| `optional`, `ask` | core only: not installed unless `init` asks `ask` and you say yes |
| `[links_if]` | `unit = ["path", …]`: links made only when that unit is installed |
| `[files]` | checkout path → system path, copied as root |
| `[binaries]` | a Rust app: `rpm` (its package), `source` (its crate), `bins` (what it builds) |
| `[verify] commands` | commands that must succeed for the unit to count as working |

A hook is re-run when the unit is first installed and whenever the unit's files or its `watch` paths change. It starts with:

```bash
#!/usr/bin/env bash
. "$(dirname "$(readlink -f "$0")")/../../../lib/hook.sh"
```

which gives it `REPO` (the checkout), `as_root` for system steps, `once NAME` for steps done only once, `info`, `ok` and `warn`, and the answers as `CCPKG_ANSWER_<ID>`.

Check the manifests before installing:

```bash
scripts/check-units.py              # keys, paths, requirements
scripts/check-units.py --packages   # also: does every package exist in dnf
```
