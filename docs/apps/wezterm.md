# WezTerm

The terminal, on `Super + Enter`.

## Builds

It comes in two builds:

| Variant | |
|---|---|
| `stable` (default) | The packaged build |
| `smear` | Built from source, with a cursor that smears as it moves |

```bash
cc-pkg-mng set wezterm variant smear
cc-pkg-mng install wezterm
```

## Author's setup

The `config-wezterm` unit, when adopted: [`config/wezterm/wezterm.lua`](../../config/wezterm/wezterm.lua). An opaque terminal, light or dark with the desktop.

| Key | Does |
|---|---|
| `Alt + Shift + S` / `V` | Splits the pane side by side / one above the other |
| `Alt + Shift + H` `J` `K` `L` | Goes to the pane on the left, below, above, on the right |
| `Alt + Shift + ←` `↓` `↑` `→` | Resizes the pane |
| `Alt + Shift + X` | Closes the pane |
| `Alt + Shift + T` / `W` | Opens / closes a tab |
| `Alt + Shift + N` / `P` or `B` | Next / previous tab |
| `Ctrl + Shift + C` / `V` | Copies / pastes |
| `Ctrl + Escape` | Copy mode: move with `h` `j` `k` `l`, select with `v`, copy with `y`, search with `/` |
| `Ctrl + 0` | Resets the font size |
| `Ctrl + Shift + F5` | Reloads the configuration |

On the desktop, `AltGr` works in place of `Alt + Shift`: `AltGr + N` goes to the next tab.

## Your own settings

Put them in `config/wezterm/local.lua` in the dotfiles folder, linked to `~/.config/wezterm/local.lua` and ignored by git, with any key from [WezTerm's configuration](https://wezterm.org/config/lua/config/). They win over the author's and reload on save.

```lua
local wezterm = require 'wezterm'
return {
  font = wezterm.font("JetBrains Mono"),
  font_size = 12,
  light = { colors = { foreground = "#1c1c1e", background = "#f5f3ee" } },
  dark  = { colors = { foreground = "#f8f8f2", background = "#101010" } },
}
```

Top-level keys apply in both modes, `light` and `dark` only when the desktop is in that mode. `colors` is merged key by key, `tab_bar` included; the tab bar follows `background` and `window_background_opacity` unless you set it. Below `1`, the opacity lets the desktop's blur show through. A new install starts from [`local.example.lua`](../../config/wezterm/local.example.lua), every setting commented with the author's value. A `color_scheme` replaces the author's colours, in one mode or both. For more control, return a `function(config, wezterm, light)` that changes `config`; `light` is `true` when the desktop is light.
