# Centre island

The middle of the bar: the active window, the workspaces and what's playing.

| Part | Use |
|---|---|
| Active window | The app's name and the window's title |
| Workspaces | A mark for each one. Click a mark to go there. Empty workspaces are hollow |
| Music | The track and its spectrum. Click to play or pause |

The island also opens [Veille](veille.md), the [key sheet](key-sheet.md) and [Programme](programme.md)'s reminders.

## Its look

Set it in `~/.config/hypr/bar-island.json`. Every key is optional. The island changes on save.

```json
{
  "shape": {
    "style": "island",
    "inset": 2,
    "innerInset": 2,
    "edgeRadius": 10,
    "innerRadius": 10,
    "fillet": 0,
    "strip": 10
  },
  "fill": { "colour": "#2c2c2e", "opacity": 0.2, "blur": false },
  "text": { "mode": "dynamic", "colour": "#f2f2f7" }
}
```

| Key | Values | Default |
|---|---|---|
| `shape.style` | `island`: a pane floating in the band. `notch`: a thin strip along the screen edge, the island hanging from it with concave fillets. `dome`: flush with the screen edge, only the band-facing corners rounded. `pill`: a capsule. `flush`: a square against the edge | `island` |
| `shape.inset` | Distance from the screen edge, in pixels, from `0` to `15` | From `style` |
| `shape.innerInset` | Distance from the band-facing edge, in pixels, from `0` to `15` | From `style` |
| `shape.edgeRadius` | Radius of the corners touching the screen edge, in pixels | From `style` |
| `shape.innerRadius` | Radius of the corners facing the band, in pixels | From `style` |
| `shape.fillet` | `notch` only: radius of the concave joint with the strip, from `0` to `15` | From `style` |
| `shape.strip` | `notch` only: thickness of the strip, from `0` to `20` | `10` |
| `fill.colour` | The island's colour, `#rrggbb`. The notch's strip wears it too | `#2c2c2e` |
| `fill.opacity` | From `0` (none) to `1` (opaque) | `0.2` |
| `fill.blur` | Blur what is behind the island | `false` |
| `text.mode` | `dynamic`: the text turns light or dark to suit the wallpaper behind each part of it. `static`: the text is always `text.colour` | `dynamic` |
| `text.colour` | The text's colour, in `static` mode only | `#f2f2f7` |

`style` fills in the other shape keys; give one yourself to override it. On a bottom bar, the edge and inner sides swap. To try each shape, save just one of these:

```json
{ "shape": { "style": "island" } }
```

```json
{ "shape": { "style": "notch" } }
```

```json
{ "shape": { "style": "dome" } }
```

```json
{ "shape": { "style": "pill" } }
```

```json
{ "shape": { "style": "flush" } }
```
