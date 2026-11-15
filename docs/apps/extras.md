# Extras

Smaller applications, and my personal setups. `init` asks whether you want each one; `cc-pkg-mng install <unit>` adds it later.

## Applications

| Unit | What it is |
|---|---|
| `brave` | The Brave browser, from Brave's own repository |
| `mangohud` | The MangoHud in-game overlay, with GOverlay to set it |
| `fastfetch` | A system summary in the terminal |
| `ccnote` | Quick notes from the terminal |
| `ccslide` | Markdown slides in the terminal, through `mdp` |

None is installed by default.

## Personal setups

If you adopt one, every file it would replace is moved to the backups first, and `cc-pkg-mng remove` puts them back.

### `config-shell`

zsh and bash with my prompt and aliases, plus zoxide, fzf, ripgrep, fd and tmux. It makes zsh your login shell, with zsh-autosuggestions and zsh-syntax-highlighting.

| To change | Edit |
|---|---|
| Aliases | [`config/bash/.bash_aliases`](../../config/bash/.bash_aliases) |
| Prompt | [`config/bash/prompt.zsh`](../../config/bash/prompt.zsh) |
| tmux | [`config/tmux/.tmux.conf`](../../config/tmux/.tmux.conf) |

### `config-wezterm` and `config-nvim`

See [WezTerm](wezterm.md#my-setup) and [Neovim](neovim.md#my-setup).

### `config-extras`

Settings for a few apps, each one only if that app is installed:

| App | File |
|---|---|
| mpv | [`config/mpv/mpv.conf`](../../config/mpv/mpv.conf) |
| MangoHud | [`config/mangohud/MangoHud.conf`](../../config/mangohud/MangoHud.conf) |
| fastfetch | [`config/fastfetch/config.jsonc`](../../config/fastfetch/config.jsonc) |
| Brave | Its flags, in [`config/brave/brave-flags.conf`](../../config/brave/brave-flags.conf) |

It also adds a launcher for CPLEX Studio's OPL IDE, shown once the IDE is installed in `/opt`.
