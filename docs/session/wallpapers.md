# Wallpapers

coucou-shell comes with its own wallpapers and GNOME's, each in a light and a dark version. Pick one with [Prisme](../tools/prisme.md), on `Super + W`.

| Set | Wallpapers |
|---|---|
| coucou Aube | Plis, Relief and Soie |
| coucou Nuit | Plis under a cold light |
| Ink | Seven per [Ink theme](theme.md), in its colours |
| GNOME | GNOME's default designs |

Credits and licences are in [`wallpapers/CREDITS.md`](../../wallpapers/CREDITS.md).

## Ink wallpapers

Each Ink theme has seven, drawn in its colours with the cartoon look's outlines and shadows: Collines, Pastilles, Coucou, Rayons, and three suns after GNOME's Dithered Sun (Soleil, Soleil collines, Soleil points).

In Prisme, a theme's band starts with its own. Glass leaves them out.

For a theme of your own, draw them into a folder listed in `wallpapers-extra.conf` (see below):

```bash
python3 ~/coucou-shell/wallpapers/coucou/ink.py --theme-dir ~/.config/hypr/themes --themes my-theme --out ~/Images/Collection
```

It needs `cjxl` (package `libjxl-utils`), `python3-cairo`, `python3-numpy` and `python3-pillow`.

## Add wallpapers

Keep them in a separate folder, `~/Images/Collection` for example. List that folder in [`prisme/wallpapers-extra.conf`](../../config/hyprland/prisme/wallpapers-extra.conf), one path per line, then run once:

```bash
bash ~/coucou-shell/config/hyprland/set_wallpapers.sh
```

After that, an image added to the folder shows in Prisme.

**Don't put files in `~/Images/Wallpapers`**: they are deleted the next time the folder is rebuilt.

To make Prisme show another folder altogether, write its path in [`prisme/wallpapers.conf`](../../config/hyprland/prisme/wallpapers.conf).

## Light and dark pairs

Name the dark version after the light one, with `-dark`: `dunes.jpg` and `dunes-dark.jpg`. The extensions can differ.

A pair is one card in Prisme. The desktop shows the version that matches light or dark mode, and switches with it.

## Fitting to the screen

Each wallpaper is fitted to the resolution of every connected screen, at install and when a new one is plugged in.

A wallpaper is cropped to fill the screen. For one that must stay whole, a portrait for example, add its file name to [`prisme/wallpaper-safe-mode.conf`](../../config/hyprland/prisme/wallpaper-safe-mode.conf), one per line (`*` stands for any text). Its sides are then filled with a blur of itself.

## Slideshow

In Prisme, `Tab` switches to a slideshow: add wallpapers with `↓`, then `Enter`.

## From a script

```bash
~/.config/hypr/scripts/wallpaper-set coucou-aube-relief.jxl
```

Give a name from the wallpaper folder, or a path.
