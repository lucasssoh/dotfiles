# The bar

The bar shows the time, the machine's figures, the workspaces and the open apps, and opens a drawer for each frequent setting.
Each block chooses the ink with better contrast against its wallpaper; any dark veil fades to clear two-thirds through the bar.

<picture><source media="(prefers-color-scheme: dark)" srcset="../screenshots/bar-dark.webp"><img src="../screenshots/bar.webp" alt="The bar"></picture>

| Area | What's there |
|---|---|
| Left | The [clock](clock-agenda.md), then the [metrics](metrics.md): CPU, temperature, fan, memory, power draw. [Programme](programme.md) sits right of the clock when it's installed |
| Centre | The [island](island.md): the active window, the workspaces and what's playing |
| Launchers | The [open apps](launchers.md) |
| Right | A [controller](../tools/manette.md) when one is connected, HDR, [audio](mixer.md) output and input, network rate, [Balise](balise.md), power profile, [battery](power.md), [notifications](notifications.md) |

Hold `Super` and the [key sheet](key-sheet.md) opens under the island. [Veille](veille.md) appears there late at night.

## Position

The bar sits at the top or at the bottom of the screen. Edit `~/.config/hypr/bar-position.json`:

```json
{ "position": "bottom" }
```

| Key | Values | Default |
|---|---|---|
| `position` | `top` or `bottom` | `top` |

The bar moves on save.

## Zen mode

`Super + Z` hides the bar, and brings it back.

## From a key or a script

Each drawer opens with a command. Bind it to a key in [`private.lua`](../session/hyprland.md#user-rules-and-keys), or call it from a script:

```bash
qs -c bar ipc call bar toggleBalise
```

| Function | Does |
|---|---|
| `toggleCalendar` | Opens or closes the calendar |
| `toggleBalise` | Balise |
| `toggleMixer` | The mixer |
| `togglePower` | The power drawer |
| `toggleNotificationCenter` | The notification centre |
| `toggleProgramme` | Programme's drawer |
| `openLibrary` | Liseuse's library |
| `controllerMenu` | The controller menu |
| `toggleZen`, `setZen true`, `setZen false` | Zen mode |
| `setDnd true`, `setDnd false` | Do not disturb |

## Screen corners

The bar rounds the screen's four corners, in the same curve as the windows. A fullscreen window covers them.

## Demo mode

`qs -c bar ipc call demo on` shows made-up figures instead of the real ones: the time, the battery, the system figures, the next event, the Wi-Fi name and what's playing. `demo off` brings the real ones back, and closes the notifications received meanwhile.
