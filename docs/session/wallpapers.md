# Wallpapers

coucou-shell comes with its own wallpapers and GNOME's, each in a light and a dark version. Pick one with [Prisme](../tools/prisme.md), on `Super + W`.

| Set | Wallpapers |
|---|---|
| coucou Aube | Plis, Relief and Soie |
| coucou Nuit | Plis under a cold light |
| GNOME | GNOME's default designs |

Credits and licences are in [`wallpapers/CREDITS.md`](../../wallpapers/CREDITS.md).

## Add your own

Keep them in a folder of your own, `~/Images/Mine` for example. List that folder in [`prisme/wallpapers-extra.conf`](../../config/hyprland/prisme/wallpapers-extra.conf), one path per line, then run once:

```bash
bash ~/coucou-shell/config/hyprland/set_wallpapers.sh
```

From then on, an image you drop in your folder shows in Prisme on its own. A listed folder that doesn't exist on this machine is skipped.

**Don't put files in `~/Images/Wallpapers`.** That folder is rebuilt from coucou-shell's wallpapers and your listed folders: a file placed there by hand is deleted at the next rebuild.

`wallpapers-extra.conf` is a file of the checkout: see [what an upgrade does to your edits](../configuration.md#what-an-upgrade-does-to-your-edits).

To make Prisme show another folder altogether, write its path in [`prisme/wallpapers.conf`](../../config/hyprland/prisme/wallpapers.conf).

## Light and dark pairs

Name the dark version after the light one, with `-dark`: `dunes.jpg` and `dunes-dark.jpg`. The extensions can differ.

A pair is one card in Prisme. The desktop shows the version that matches light or dark mode, and switches with it.

## Fitting to the screen

Each wallpaper is fitted to the resolution of every connected screen, at install and when you plug in a new screen. Until then, that screen shows the original.

A wallpaper is cropped to fill the screen. For one that must stay whole, a portrait for example, add its file name to [`prisme/wallpaper-safe-mode.conf`](../../config/hyprland/prisme/wallpaper-safe-mode.conf), one per line (`*` stands for any text). Its sides are then filled with a blur of itself.

The fitted copies are in `~/.cache/filtered_wallpapers/<width>x<height>/`.

## Slideshow

In Prisme, `Tab` switches to a slideshow: add wallpapers with `↓`, then `Enter`.

## From a script

```bash
~/.config/hypr/scripts/wallpaper-set coucou-aube-relief.jxl
```

A name is looked up in the wallpaper folder. A path works too.

Your current choice is kept in `~/.config/hypr/wallpaper-playlist.json`. Prisme writes it; there's nothing to edit there.
