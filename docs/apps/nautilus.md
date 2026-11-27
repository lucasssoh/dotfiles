# Nautilus

The file manager, on `Super + E`.

- Under each name: a folder's item count, a file's size.
- Under the home folder and each mounted drive in the sidebar: a gauge of the disk space used. Hover it for the free space.
- Folders take the [shell theme](../session/theme.md#nautilus-and-the-viewers)'s folder colour.
- In the cartoon look, it takes the theme's colours, font and outlines, and changes with the theme at once.

| To change | Do this |
|---|---|
| What shows under the names | Nautilus's menu, *Preferences*, *Grid view captions* |
| The cartoon look | Edit [`config/nautilus/ink.css`](../../config/nautilus/ink.css), then run `~/.config/hypr/scripts/shell-theme.py sync` |

Set up with Nemo before, the next `cc-pkg-mng upgrade` installs Nautilus and gives it the folders, once. Nemo stays available: install the `nemo` unit, then make it the [default for folders](../session/hyprland.md#default-applications).
