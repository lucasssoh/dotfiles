# Theme and fonts

The colours of GTK apps, the icons, the cursor and the fonts.

## Light and dark

The Dark mode tile in [Balise](../bar/balise.md) switches the shell, GTK apps and browsers. Light and dark [wallpapers](wallpapers.md#light-and-dark-pairs) follow.

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
