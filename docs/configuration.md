# Configuration

This page covers what you can change around the manager, and how to write a unit of your own. The commands themselves are in [cc-pkg-mng.md](cc-pkg-mng.md), and what each unit installs (and where its settings live) is in [modules.md](modules.md).

## Editing coucou-shell

Configuration files are **linked** from the checkout into place, never copied. So you edit the file in the checkout, and the change takes effect as soon as the program reloads it.

After an edit, `cc-pkg-mng status` shows the unit as *changed since installed*. Some changes need more than a reload, like a new package or a hook. For those, run `cc-pkg-mng install <unit>` to apply it again.

On the stable channel, commit or stash your edits before you `upgrade`. It won't move over uncommitted changes.

## Environment variables

| Variable | Default | Effect |
|---|---|---|
| `COUCOU_SHELL_URL` | `https://github.com/lucasssoh/dotfiles.git` | What `init` clones |
| `CCPKG_STATE_DIR` | `~/.local/state/coucou-shell` | Where the manager keeps its state, backups and logs |
| `CARGO_TARGET_ROOT` | `~/.cache/dotfiles/cargo-target` | Where Roue, Prisme, Balise and Manette are built on edge |
| `HOST_PROFILE` | taken from the machine's DMI product name | Forces a machine profile. See [per-machine profiles](modules.md#per-machine-profiles) |

## Adding a unit

A unit is a folder, `units/<layer>/<name>/`, with a `unit.toml` inside. Once it's there, `cc-pkg-mng list` shows it and `cc-pkg-mng install <name>` installs it.

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

A few more keys, for less common cases:

| Key | Use |
|---|---|
| `optional`, `ask` | Core units only. The unit isn't installed unless `init` asks the `ask` question and you say yes |
| `[links_if]` | `unit = ["path", …]`: links that are only made when that other unit is installed |
| `[files]` | Checkout path → system path, copied as root |
| `[binaries]` | For a Rust app: `rpm` (its package), `source` (its crate), `bins` (what it builds) |
| `[verify] commands` | Commands that must succeed for the unit to count as working |

A hook runs the first time the unit is installed, and again whenever the unit's files or its `watch` paths change. Start it with:

```bash
#!/usr/bin/env bash
. "$(dirname "$(readlink -f "$0")")/../../../lib/hook.sh"
```

That gives your script a few helpers:
- `REPO`, the path to the checkout;
- `as_root`, for steps that need root;
- `once NAME`, for steps that should only ever run once;
- `info`, `ok` and `warn`, to print messages;
- your answers, as `CCPKG_ANSWER_<ID>`.

You can check your manifests before installing anything:

```bash
scripts/check-units.py              # keys, paths, requirements
scripts/check-units.py --packages   # also checks that every package exists in dnf
```
