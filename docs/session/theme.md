# Theme and fonts

The colours of GTK apps, the icons, the cursor and the fonts.

## Light and dark

The Dark mode tile in [Balise](../bar/balise.md) switches the shell, GTK apps and browsers. Light and dark [wallpapers](wallpapers.md#light-and-dark-pairs) follow.

## The shell theme

`~/.config/hypr/shell-theme.json` switches the whole shell between its two looks:

```json
{ "style": "cartoon" }
```

| `style` | Look |
|---|---|
| `default` | The regular glass bar, panes and MiSans interface font |
| `cartoon` | Rounded panels with heavy black outlines and hard offset shadows, pastel accents, and the rounded Fredoka font |

Cartoon covers the bar, the OSD, notifications and toasts, the controller's popup and face buttons, the mixer, the key sheet and Hyprland's window borders (a pronounced outline and no shadow at all — a lighter grey on a dark desktop, black on a light one, with a lower-contrast outline for idle windows — instead of the glass gradient and halo). Inside every drawer, the tiles, rows, buttons, switches, fields, segments and charts are inked too: Balise, Power, the calendar, Programme, the launcher, Sesame and the library.

The bar keeps its own hierarchy and the way its shapes are drawn: `style`, zone shapes, `radius`, opacities and text modes still come from [`bar.json`](../bar/island.md#its-look), and the band, notches and fillets are drawn exactly as in the default look. For now only the centre zone is repainted (lilac, or copper in `cuivre-cyan`): the band and the sides keep the fills, text and shapes written in `bar.json`. The centre block and every workspace mark keep a strong ink outline, with larger circular states for the workspaces; the side groups, audio and battery stay unframed. Cartoon is opaque throughout. The faint fading top-edge reflection is reserved for the global drawer containers, controls that are on, and key sheet keys that are active but not held; other elements stay flat. Accents mark what matters: lemon for the current workspace, lilac for an upcoming appointment. In `cuivre-cyan`, the extra indigo and sage sort the controls by category — copper for Wi-Fi, profile and dark mode, indigo for Bluetooth and display, sage for Ethernet, fast charge and power states. The heaviest Fredoka weights are softened at the bar's small text sizes. Saving `shell-theme.json` changes the look on the running shell, without a restart.

Optional keys let you tune the cartoon look:

| Key | Default | Effect |
|---|---|---|
| `palette` | `pastel` | Colourway of the cartoon look: `pastel` (lilac/lemon/mint) or `cuivre-cyan` (copper #EDA16B, cyan #74CCD2, indigo #8FA6DC and sage #A9C7A0 on #292929 shells and #3b3b3b cards) |
| `font` | `Fredoka` | Interface font family, if you prefer another rounded face |
| `outline` | `3` | Outline thickness, from 1 to 6 px |
| `radius` | `18` | Base corner radius, from 12 to 32 px |
| `accent` | `#c9baf5` | The main pastel, used for active controls |

A missing file means `default`. Fredoka is installed by `cc-pkg-mng install fonts` (SIL Open Font License 1.1).

## Colours

GTK3 apps (Nemo, file dialogs) take the shell's colours, light or dark. The icons are Papirus, the cursor Comix Cursors.

| To change | Edit this, then run `cc-pkg-mng install theme` |
|---|---|
| The colours | [`theme/palette-dark.css`](../../config/nemo/theme/palette-dark.css) and [`theme/palette-light.css`](../../config/nemo/theme/palette-light.css). Restart Nemo to see them |
| The shapes (Nemo, buttons, menus, dialogs) | [`theme/overlay.css`](../../config/nemo/theme/overlay.css). Restart Nemo to see it |

## Fonts

| Font | Used for |
|---|---|
| MiSans Latin | The interface: the shell, GTK and Qt apps, and web pages that ask for a plain sans-serif |
| JetBrains Mono, Iosevka, Cascadia Code (Nerd Fonts) | Terminals and code |
