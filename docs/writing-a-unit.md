# Writing a unit

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
