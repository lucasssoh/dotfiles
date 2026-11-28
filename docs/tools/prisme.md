# Prisme

The wallpaper picker, on `Super + W`.

<picture><source media="(prefers-color-scheme: dark)" srcset="../screenshots/prisme-dark.webp"><img src="../screenshots/prisme.webp" alt="Prisme"></picture>

The selected wallpaper shows as a live preview, in the middle of the blurred desktop, with a sketch of the desktop over it in the theme's look and colours. Under it, one band of wallpapers per [shell theme](../session/theme.md): Glass first, then each Ink theme, named `Ink · Bamboo`, `Ink · Nord`… Prisme sets the theme and the wallpaper together.

## Keys

| Key | Does |
|---|---|
| `←` `→`, `h` `l` | Previous or next wallpaper |
| `↑` `↓`, `k` `j` | Previous or next theme: the band above or below |
| `Enter`, `Space` | Sets the wallpaper, and the theme if you changed it |
| `Esc`, `q` | Closes, and keeps the current one |
| `C` | Previews in the other mode, light or dark |
| `Tab` | Switches between one wallpaper and a slideshow |
| `Shift` + `↓`, `Shift` + `J` | In a slideshow, adds the wallpaper |
| `Shift` + `↑`, `Shift` + `K` | In a slideshow, removes it |

A click on a band above or below, or on its name, goes to that theme.

To change them, edit `~/.config/prisme/keymap.conf`: one line per action, several keys separated by commas.

## Bands

Glass has every wallpaper except the [Ink ones](../session/wallpapers.md#ink-wallpapers). An Ink theme's band starts with its own Ink wallpapers, then the others whose colours suit it, best first. Each band stays on the wallpaper you left it on.

## Light and dark pairs

A wallpaper that comes in light and dark is one card. It shows the version for the current mode, and the desktop switches version with the mode. To make a pair, see [wallpapers](../session/wallpapers.md#light-and-dark-pairs).

## Settings

In `~/.config/prisme/`:

| File | Sets |
|---|---|
| `wallpapers.conf` | The folder Prisme shows. One path. `~/Images/Wallpapers` when empty |
| `wallpapers-extra.conf` | User folders to add to it. See [wallpapers](../session/wallpapers.md#add-wallpapers) |
| `wallpaper-safe-mode.conf` | The wallpapers never to crop. See [wallpapers](../session/wallpapers.md#fitting-to-the-screen) |
| `keymap.conf` | The keys |
| `style.css` | Colours and sizes |
