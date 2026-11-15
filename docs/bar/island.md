# Centre island

The middle of the bar: the active window, your workspaces and what's playing.

| Part | Use |
|---|---|
| Active window | The app's name and the window's title |
| Workspaces | A mark for each one. Click a mark to go there. Empty workspaces are hollow |
| Music | The track and its spectrum. Click to play or pause |

The island also opens [Veille](veille.md), the [key sheet](key-sheet.md) and [Programme](programme.md)'s reminders.

## Its look

Set it in `~/.config/hypr/bar-island.json`. Every key is optional. The island changes as soon as you save.

```json
{
  "mode": "dynamic",
  "background": "#2c2c2e",
  "opacity": 0.2,
  "blur": false,
  "text": "#f2f2f7"
}
```

| Key | Values | Default |
|---|---|---|
| `mode` | `dynamic`: the text turns light or dark to suit the wallpaper behind each part of it. `static`: the text is always `text` | `dynamic` |
| `background` | The island's colour, `#rrggbb` | `#2c2c2e` |
| `opacity` | From `0` (none) to `1` (opaque) | `0.2` |
| `blur` | Blur what is behind the island | `false` |
| `text` | The text's colour, in `static` mode only | `#f2f2f7` |
