# Theme and fonts

The colours of GTK apps, the icons, the cursor and the fonts.

## Light and dark

The Dark mode tile in [Balise](../bar/balise.md) switches the shell, GTK apps and browsers. Light and dark [wallpapers](wallpapers.md#light-and-dark-pairs) follow.

## The shell theme

`~/.config/hypr/shell-theme.json` only selects the look and the theme:

```json
{ "style": "cartoon", "theme": "cuivre-cyan" }
```

| `style` | Look |
|---|---|
| `default` | The regular glass bar, panes and MiSans interface font |
| `cartoon` | The inked, rounded look described below |

## Theme files

Each theme is one file in `~/.config/hypr/themes/<id>.json`, with one schema and both light and dark modes in the same file. Eighteen ship with the shell: `coucou` (the default, Neovim's coucou palette), `pastel`, `cuivre-cyan`, and bamboo, catppuccin, darkvoid, dracula, everforest, gruvbox, jellybeans-nvim, kanagawa, melange, nightfox, nord, oceanic-next, onedark, rose-pine and tokyonight. Add your own next to them.

```json
{
  "schema": "coucou-theme/1",
  "name": "My theme",
  "font": "Fredoka",
  "geometry": { "outline-width": 3 },
  "modes": {
    "dark": {
      "surfaces": {
        "panel": "#292929",
        "card": "#3b3b3b",
        "card-hover": "#474747",
        "card-raised": "#505050",
        "card-sunken": "#1f1f1f"
      },
      "text": {
        "primary": "#f1eee6",
        "secondary": "#c8c8c4",
        "muted": "#a0a09c",
        "faint": "#757570",
        "on-accent": "#000000"
      },
      "accents": {
        "active": "#eda16b",
        "highlight": "#74ccd2",
        "success": "#a9c7a0",
        "info": "#8fa6dc",
        "warning": "#eda16b",
        "danger": "#eda16b"
      },
      "outline": "#000000",
      "shadow": "#000000"
    },
    "light": { "...": "the same keys, with your light colours" }
  }
}
```

Every key above is required in both modes, as `#rrggbb`. While a theme is missing or invalid, `coucou` stands in. Saving a theme recolours the running shell.

Four keys are optional:

| Key | What it sets | Without it |
|---|---|---|
| `folder` (next to `font`) | The folders' colour in the file manager | `accents.info` of the dark mode |
| `accents.blue`, `accents.magenta`, `accents.cyan` | The terminal's blue, magenta and cyan | `info`, `warning` and `active` |

| Key | Where it shows |
|---|---|
| `surfaces.panel` | Drawer panels, sheet backgrounds, the bar's band and sides |
| `surfaces.card`, `card-hover`, `card-raised`, `card-sunken` | Cards inside the drawers |
| `text.primary`, `secondary`, `muted`, `faint` | Text inside the drawers |
| `text.on-accent` | Text on an accent fill |
| `accents.active` | Active tiles, Wi-Fi, dark mode, the centre zone |
| `accents.highlight` | Current workspace, today in the calendar, the brightness level |
| `accents.success` | Fast charge and other good states |
| `accents.info` | Bluetooth, display and night controls |
| `accents.warning`, `accents.danger` | Warnings and alerts |
| `outline`, `shadow` | Inked edges and shadows |
| `geometry.outline-width` | Outline thickness. Corners come from [`bar.json`](../bar/island.md#its-look) |
| `font` | Interface font family |

`Super + Shift + W` lists Glass and every theme by its `name`. Glass keeps the theme, for when you switch back.

## WezTerm and Neovim

They take the selected theme's colours, light or dark, and follow when it changes. In Neovim, the `coucou` colorscheme takes the whole palette; any other colorscheme keeps its colours on the theme's background, except with `--bg=transparent`.

## Nautilus and the viewers

In the cartoon look, [Nautilus](../apps/nautilus.md), Nemo, other apps' file dialogs, [swayimg](../apps/swayimg.md), [Liseuse](../tools/liseuse.md) and the [font viewer](../tools/fontview.md) take the theme's colours and font. In Nautilus, the buttons, the current folder and place, a selected file with its name, the disk gauges and the status pill carry the outline, and folders take the theme's folder colour. Nautilus, Nemo and the font viewer change with the theme at once, swayimg and Liseuse the next time they open.

## Colours

GTK3 apps (Nemo, file dialogs) take the shell's colours, light or dark. The icons are Coucou: Adwaita's, with folders in the theme's colour in the cartoon look. The cursor is Comix Cursors.

| To change | Edit this, then run `cc-pkg-mng install theme` |
|---|---|
| The colours | [`theme/palette-dark.css`](../../config/nemo/theme/palette-dark.css) and [`theme/palette-light.css`](../../config/nemo/theme/palette-light.css). Restart Nemo to see them |
| The shapes (Nemo, buttons, menus, dialogs) | [`theme/overlay.css`](../../config/nemo/theme/overlay.css). Restart Nemo to see it |
| The cartoon look in Nemo and dialogs | [`theme/ink.css`](../../config/nemo/theme/ink.css). Run `~/.config/hypr/scripts/shell-theme.py sync` to see it |

## Fonts

| Font | Used for |
|---|---|
| MiSans Latin | The interface: the shell, GTK and Qt apps, and web pages that ask for a plain sans-serif |
| Adwaita Mono | WezTerm |
| JetBrains Mono, GoogleSansCode, Iosevka, Cascadia Code (Nerd Fonts) | Other terminals and code, and a [choice in WezTerm](../apps/wezterm.md#your-own-settings) |
