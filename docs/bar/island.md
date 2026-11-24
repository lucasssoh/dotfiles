# Centre island

The middle of the bar: the active window, the workspaces and what's playing.

| Part | Use |
|---|---|
| Active window | The app's name and the window's title |
| Workspaces | A mark for each one. Click a mark to go there. Empty workspaces are hollow |
| Music | The track and its spectrum. Click to play or pause |

The island also opens [Veille](veille.md), the [key sheet](key-sheet.md) and [Programme](programme.md)'s reminders.

## Its look

The bar's position and look live in one file, `~/.config/hypr/bar.json`. Every key is optional. Saving the file restarts the bar, so the new edge and the new look apply together.

There are three independent levels: the **bar** itself at the top level, then the **center** and **sides** zones sitting on it. The top level never becomes a zone's fill — a zone with no `fill` of its own is transparent and shows the bar beneath it.

```json
{
  "position": "top",
  "style": "solid",
  "radius": 18,
  "fill": { "colour": "#000000", "opacity": 1, "blur": false },
  "text": { "mode": "dynamic", "colour": "#FFFFFF" },
  "center": {
    "style": "flush",
    "fill": { "colour": "#000000", "opacity": 1, "blur": false },
    "text": { "mode": "dynamic", "colour": "#FFFFFF" }
  },
  "sides": {
    "style": "notch",
    "fill": { "colour": "#000000", "opacity": 1, "blur": false },
    "text": { "mode": "dynamic", "colour": "#FFFFFF" }
  }
}
```

| Bar key | Values | Default |
|---|---|---|
| `position` | `top` or `bottom` (see [Position](index.md#position)) | `top` |
| `style` | `solid`: one plain bar with concave corners under it and a gap to the windows. `floating`: a translucent band with detached blocks | `floating` |
| `radius` | `0`–`32`: the curve shared by window corners, the bar's concave corners and fillets, the convex blocks and the screen corners | `18` |
| `fill.colour` | The bar's own colour, `#rrggbb` or `#rrggbbaa` | near-black; opaque in `solid`, ~45 % in `floating` |
| `fill.opacity` | From `0` (none) to `1` (opaque) | `1` in `solid`, `0.45` in `floating` |
| `fill.blur` | Blur what is behind the bar | `false` |
| `text.mode` | `dynamic`: text follows the wallpaper through the bar's fill. `static`: always `text.colour` | `dynamic` (`static` for the centre in `solid`) |
| `text.colour` | The bar's text colour in `static` mode | Light or dark with the system |
| `light`, `dark` | `fill` and `text` overrides for one mode | The values above |

| Zone key | Values | Default |
|---|---|---|
| `style` | `center`: `island`, `notch`, `dome`, `pill`, `flush`. `sides`: `none`, `island`, `notch`, `pill` | `island` / `none` |
| `fill.colour` | The zone's own colour, over the bar | Transparent |
| `fill.opacity` | From `0` (none) to `1` (opaque) | `0` when no colour is set, `1` when one is |
| `fill.blur` | Blur what is behind the centre island (centre only) | `false` |
| `text.mode` | `dynamic`: the zone's text follows what it really draws — `fill.colour` at `fill.opacity` over `bar-tint.py`'s wallpaper profile. `static`: always `text.colour` | `dynamic` (`static` for the centre in `solid`) |
| `text.colour` | The zone's text colour in `static` mode | The bar's text colour |
| `light`, `dark` | `fill` and `text` overrides for one zone in one mode | The zone's values |

Both zone shapes are honoured in `solid` too: the side shapes are drawn over the bar's surface. `shape` is accepted as an alias of a zone's `style`, and a string shortcut still works (`"center": "notch"`). Old flat configs, with no zone object, still get their fill on both zones as before. The old `bar-island.json` and `bar-position.json` are still read while `bar.json` is missing; installing the bar moves them into it and keeps them as `*.old`.

`radius` is the one curve for the whole shell. Saving it writes `~/.config/hypr/bar-radius` for Hyprland's own config and applies `decoration:rounding` immediately; the bar's concave corners, notch fillets, blocks, drawer rows and [screen corners](index.md#screen-corners) follow the same number. Small shapes clamp it to half their height, so a 24px block becomes a full pill while a drawer stays under its own limit. Drawers that open wider keep their larger 28–32px corners.

## Shapes to try

Change just one key, save, and the bar restarts. The centre:

```json
{ "center": { "style": "island" } }
```

```json
{ "center": { "style": "notch" } }
```

```json
{ "center": { "style": "dome" } }
```

```json
{ "center": { "style": "pill" } }
```

```json
{ "center": { "style": "flush" } }
```

A different colour for the bar, the centre and the sides:

```json
{
  "style": "solid",
  "fill": { "colour": "#101010", "opacity": 1 },
  "center": {
    "style": "flush",
    "fill": { "colour": "#3a2a5a", "opacity": 0.8 },
    "text": { "mode": "static", "colour": "#ffffff" }
  },
  "sides": {
    "style": "notch",
    "fill": { "colour": "#006644", "opacity": 0.8 },
    "text": { "mode": "static", "colour": "#ffffff" }
  }
}
```

Different colours in light and dark mode, per zone:

```json
{
  "style": "solid",
  "fill": { "colour": "#000000" },
  "center": {
    "fill": { "colour": "#101010" },
    "light": { "fill": { "colour": "#f5f3ee" }, "text": { "colour": "#1c1c1e" } }
  },
  "sides": {
    "fill": { "colour": "#3a2a5a" },
    "dark": { "text": { "mode": "static", "colour": "#00ffcc" } }
  }
}
```
