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

The `config-wezterm` unit, when adopted: [`config/wezterm/wezterm.lua`](../../config/wezterm/wezterm.lua). It turns light or dark with the desktop.

| Key | Does |
|---|---|
| `Alt + Shift + S` / `V` | Splits the pane side by side / one above the other |
| `Alt + Shift + H` `J` `K` `L` | Goes to the pane on the left, below, above, on the right |
| `Alt + Shift + ←` `↓` `↑` `→` | Resizes the pane |
| `Alt + Shift + X` | Closes the pane |
| `Alt + Shift + T` / `W` | Opens / closes a tab |
| `Alt + Shift + N` / `P` | Next / previous tab |
| `Ctrl + Shift + C` / `V` | Copies / pastes |
| `Ctrl + Escape` | Copy mode: move with `h` `j` `k` `l`, select with `v`, copy with `y`, search with `/` |
| `Ctrl + 0` | Resets the font size |
| `Ctrl + Shift + F5` | Reloads the configuration |
