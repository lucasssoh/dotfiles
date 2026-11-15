# Displays

Which screens are on, where they sit, their scale, HDR and night mode.

After your first login, every screen is on at its preferred mode. With two screens, workspaces 1 to 5 are on the main one and 6 to 10 on the other.

The files below are in `~/.config/hypr/`. A missing file means the defaults.

## Which screens are on

Press `Super + O` and pick on the wheel: both screens, the laptop's only, or the external one only. See [Roue](../tools/roue.md).

The wheel writes `display-layout.json`, which you can edit too:

```json
{ "mode": "both", "main": "internal" }
```

| Key | Values | Default |
|---|---|---|
| `mode` | `both`, `internal`, `external` | `both` |
| `main` | `internal` or `external`: the screen that holds workspaces 1 to 5 | `internal` |

`internal` is the laptop's panel, `external` any other screen.

## Where they sit

Edit `monitor-layout.json`:

```json
{ "grid": [["external", "internal"]], "align": "center" }
```

| Key | Values | Default |
|---|---|---|
| `grid` | Rows of screens, left to right. One row puts them side by side; one screen per row stacks them. `null` leaves a gap | one row, external screens then the laptop's |
| `align` | `start`, `center` or `end`: where a smaller screen sits beside a larger one | `center` |

A second and a third external screen are `external2` and `external3`:

```json
{ "grid": [["external", "external2"], ["internal", null]] }
```

To swap the laptop and the external screen:

```bash
~/.config/scripts/display-layout.sh swap
```

`hyprctl reload` applies an edit.

## Scale

Edit `scale.json`:

```json
{ "internal": 1.25, "external": 1 }
```

| Key | Values | Default |
|---|---|---|
| `internal` | The laptop panel's scale | `1` |
| `external` | The scale of every external screen | `1` |

## HDR

Turn HDR on or off from the HDR tile in [Balise](../bar/balise.md), for the screen the drawer is on. `hdr` shows in the bar while it's on.

Each screen keeps its own setting.

```bash
~/.config/hypr/scripts/hdr.sh debug    # what the screen and Hyprland agreed on
```

## Night mode

`Super + N`, or the Night mode tile in Balise, warms the colours until you turn it off.

The warmth is 4900 K. To change it, edit the `--temperature` value in [`toggle-night-mode.sh`](../../config/hyprland/scripts/toggle-night-mode.sh): lower is warmer.

## Brightness

The brightness keys and the slider in Balise. Brightness never reaches 0. On an OLED panel whose keys do nothing, see [hardware](../hardware.md#things-to-do-by-hand).
