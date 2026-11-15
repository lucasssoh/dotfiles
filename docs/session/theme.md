# Theme and fonts

The colours of GTK apps, the icons, the cursor and the fonts.

## Light and dark

The Dark mode tile in [Balise](../bar/balise.md) switches the shell, GTK apps and browsers. Light and dark [wallpapers](wallpapers.md#light-and-dark-pairs) follow.

## Colours

The `theme` unit gives every GTK3 app (Nemo, the file chooser) the shell's colours, through two generated themes in `~/.local/share/themes/`, `Adwaita-dark` and `Adwaita-light`, which follow the desktop's light or dark setting. It also brings the Papirus icons, Comix Cursors (built if `~/.icons/ComixCursors-White` is missing) and the Qt settings.

| To change | Edit this, then run `cc-pkg-mng install theme` |
|---|---|
| The colours | [`theme/palette-dark.css`](../../config/nemo/theme/palette-dark.css) and [`theme/palette-light.css`](../../config/nemo/theme/palette-light.css), copies of `quickshell/bar/theme/DrawerTheme.qml`. Restart Nemo to see them |
| The shapes (Nemo, buttons, menus, dialogs) | [`theme/overlay.css`](../../config/nemo/theme/overlay.css). Restart Nemo to see it |
| How GTK's own colours are remapped | [`theme/build-themes.py`](../../config/nemo/theme/build-themes.py) |

## Fonts

The `fonts` unit downloads the JetBrains Mono, Iosevka and Cascadia Code Nerd Fonts and MiSans Latin into `~/.local/share/fonts/` if they're missing, along with the icon fonts the bar uses (Phosphor, Lucide, MingCute, GoogleSansCode Nerd Font Mono). It also links the fontconfig rule and sets the interface font.

The interface font is MiSans Latin, in the shell, GTK and Qt apps, and on web pages that ask for a plain sans-serif.
