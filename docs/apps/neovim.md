# Neovim

The editor. The `neovim` unit installs it on its own, with no configuration.

## My setup

The `config-nvim` unit, if you adopt it: `init.lua`, `lua/`, `ftplugin/`, `colors/` and `bin/`, linked into `~/.config/nvim/`. Folders are linked as a whole, so a new file under `config/nvim/lua/` works straight away.

| Feature | How to use it |
|---|---|
| Theme | `:SetTheme coucou` sets the colour scheme. `--auto` follows the desktop's light or dark mode (the default), `--light` and `--dark` fix it. `--bg=transparent` shows the terminal's background, `--bg=black` makes it black |
| Live Markdown preview | `Alt + P` opens a GTK 4 window that updates block by block, maths included |
| Python | Pyright completion and diagnostics, plus Ruff linting. The game's `.py` scripts use the same setup |
| PlantUML | Highlighting, linting, completion, and a live preview window. `:PumlFromJava` draws a class diagram from Java sources, and `:PumlExport` exports it |

The optional tools are just that: without `plantuml-lsp` you lose PlantUML completion, and without MathJax the preview shows maths as raw TeX. Everything else keeps working.

| Key | Does |
|---|---|
| `Space` | The leader key |
| `Space e` | Shows or hides the file tree |
| `Tab` / `Shift + Tab` | Next / previous open file |
| `Space x` | Closes the file. `Space X` discards its changes |
| `Space h` `j` `k` `l` | Goes to the window on the left, below, above, on the right |
| `gz` | Shows the diagnostic under the cursor |

The other keys are in [`config/nvim/lua/keymaps.lua`](../../config/nvim/lua/keymaps.lua).
